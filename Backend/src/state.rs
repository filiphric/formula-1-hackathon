use chrono::{DateTime, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;

pub const TOPICS: [&str; 7] = [
    "drivers",
    "position",
    "intervals",
    "laps",
    "stints",
    "race_control",
    "location",
];

#[derive(Clone, Debug, Deserialize)]
pub struct Session {
    pub session_key: i64,
    pub session_name: String,
    pub circuit_short_name: String,
    pub date_start: String,
    pub date_end: String,
}

// This is the existing Swift Codable contract. Keep camelCase output keys stable.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub mode: String,
    pub upstream: String,
    pub updated_at: Option<String>,
    pub session: Option<SessionView>,
    pub drivers: Vec<Driver>,
    pub messages: Vec<RaceMessage>,
    #[serde(default)]
    pub track: Option<TrackLayout>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SessionView {
    pub name: String,
    pub circuit: String,
    pub start: String,
    pub end: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Driver {
    pub number: i64,
    pub name: String,
    pub acronym: String,
    pub team: String,
    pub color: String,
    pub position: Option<i64>,
    pub gap: Option<String>,
    pub lap: Option<i64>,
    pub lap_time: Option<f64>,
    pub compound: Option<String>,
    #[serde(default)]
    pub location: Option<DriverLocation>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RaceMessage {
    pub id: String,
    pub date: String,
    pub message: String,
    pub flag: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TrackPoint {
    pub x: f64,
    pub y: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DriverLocation {
    pub x: f64,
    pub y: f64,
    pub date: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackLayout {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rotation_degrees: Option<f64>,
    pub source: String,
    pub points: Vec<TrackPoint>,
}

fn location(record: &Value) -> Option<DriverLocation> {
    let x = record["x"].as_f64()?;
    let y = record["y"].as_f64()?;
    if !x.is_finite() || !y.is_finite() || (x == 0.0 && y == 0.0) {
        return None;
    }
    event_date(record)?;
    Some(DriverLocation {
        x,
        y,
        date: record["date"].as_str()?.into(),
    })
}

pub struct TimingState {
    pub mode: String,
    pub upstream: String,
    pub session: Option<Session>,
    pub track: Option<TrackLayout>,
    records: HashMap<String, HashMap<String, Value>>,
    updated_at: Option<DateTime<Utc>>,
}

fn event_date(record: &Value) -> Option<DateTime<Utc>> {
    record
        .get("date")
        .or_else(|| record.get("date_start"))
        .and_then(Value::as_str)
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.with_timezone(&Utc))
}

impl TimingState {
    pub fn new(mode: &str) -> Self {
        Self {
            mode: mode.into(),
            upstream: "connecting".into(),
            session: None,
            track: None,
            records: HashMap::new(),
            updated_at: None,
        }
    }

    pub fn set_session(&mut self, session: Session) {
        if self.session.as_ref().map(|s| s.session_key) != Some(session.session_key) {
            self.records.clear();
            self.track = None;
            self.updated_at = None;
        }
        self.session = Some(session);
    }

    pub fn apply(&mut self, topic: &str, record: Value) {
        if !TOPICS.contains(&topic)
            || self.session.as_ref().map(|s| s.session_key)
                != record.get("session_key").and_then(Value::as_i64)
            || self.session.is_none()
        {
            return;
        }
        if topic == "location" && location(&record).is_none() {
            return;
        }
        let key = if topic == "race_control" {
            let (Some(date), Some(message)) = (record["date"].as_str(), record["message"].as_str())
            else {
                return;
            };
            format!("{date}:{message}")
        } else {
            let Some(number) = record["driver_number"].as_i64() else {
                return;
            };
            number.to_string()
        };
        let bucket = self.records.entry(topic.into()).or_default();
        let mut preserve_live_fields = false;
        if let Some(old) = bucket.get(&key) {
            if topic == "location" && event_date(&record) < event_date(old) {
                return;
            }
            let sequence = |r: &Value| match topic {
                "laps" => r["lap_number"].as_i64().unwrap_or(0),
                "stints" => r["stint_number"].as_i64().unwrap_or(0),
                _ => 0,
            };
            if sequence(&record) < sequence(old) {
                return;
            }
            if sequence(&record) == sequence(old) {
                // REST has no stream revision ID. For equal event times, keep live
                // corrections while still hydrating fields missing from the stream.
                preserve_live_fields = record["_id"].is_null()
                    && !old["_id"].is_null()
                    && event_date(&record) <= event_date(old);
                if let (Some(a), Some(b)) = (record["_id"].as_i64(), old["_id"].as_i64()) {
                    if a < b {
                        return;
                    }
                } else if let (Some(a), Some(b)) = (event_date(&record), event_date(old)) {
                    if a < b {
                        return;
                    }
                }
            }
        }
        let date = event_date(&record);
        // Merge partial corrections without dropping fields absent from the update.
        let mut merged = bucket.get(&key).cloned().unwrap_or_else(|| json!({}));
        if let (Some(target), Some(source)) = (merged.as_object_mut(), record.as_object()) {
            if preserve_live_fields {
                for (field, value) in source {
                    target.entry(field.clone()).or_insert_with(|| value.clone());
                }
            } else {
                target.extend(source.clone());
            }
        }
        bucket.insert(key, merged);
        if topic == "race_control" && bucket.len() > 100 {
            if let Some(oldest) = bucket
                .iter()
                .min_by_key(|(_, r)| event_date(r))
                .map(|(k, _)| k.clone())
            {
                bucket.remove(&oldest);
            }
        }
        if let Some(date) = date.filter(|_| topic != "location") {
            if self.updated_at.is_none_or(|old| date > old) {
                self.updated_at = Some(date);
            }
        }
    }

    fn record(&self, topic: &str, key: &str) -> &Value {
        self.records
            .get(topic)
            .and_then(|b| b.get(key))
            .unwrap_or(&Value::Null)
    }

    pub fn snapshot(&self) -> Snapshot {
        let mut drivers: Vec<Driver> = self
            .records
            .get("drivers")
            .into_iter()
            .flat_map(|b| b.iter())
            .map(|(key, d)| {
                let number = d["driver_number"].as_i64().unwrap_or(0);
                let text =
                    |field: &str, fallback: &str| d[field].as_str().unwrap_or(fallback).to_string();
                let acronym = text("name_acronym", &number.to_string());
                let gap = &self.record("intervals", key)["gap_to_leader"];
                Driver {
                    number,
                    name: text("full_name", &acronym),
                    acronym,
                    team: text("team_name", "Unknown team"),
                    color: text("team_colour", "888888"),
                    position: self.record("position", key)["position"].as_i64(),
                    gap: gap
                        .as_f64()
                        .map(|n| format!("+{n:.3}"))
                        .or_else(|| gap.as_str().map(str::to_string)),
                    lap: self.record("laps", key)["lap_number"].as_i64(),
                    lap_time: self.record("laps", key)["lap_duration"].as_f64(),
                    location: location(self.record("location", key)),
                    compound: self.record("stints", key)["compound"]
                        .as_str()
                        .map(str::to_string),
                }
            })
            .collect();
        drivers.sort_by_key(|d| (d.position.unwrap_or(i64::MAX), d.number));
        let mut messages: Vec<RaceMessage> = self
            .records
            .get("race_control")
            .into_iter()
            .flat_map(|b| b.iter())
            .map(|(key, r)| RaceMessage {
                id: key.clone(),
                date: r["date"].as_str().unwrap_or_default().into(),
                message: r["message"].as_str().unwrap_or_default().into(),
                flag: r["flag"].as_str().map(str::to_string),
            })
            .collect();
        messages.sort_by(|a, b| {
            let parse = |s: &str| DateTime::parse_from_rfc3339(s).ok();
            parse(&b.date)
                .cmp(&parse(&a.date))
                .then_with(|| a.id.cmp(&b.id))
        });
        let mut snapshot = Snapshot {
            mode: self.mode.clone(),
            upstream: self.upstream.clone(),
            updated_at: self
                .updated_at
                .map(|d| d.to_rfc3339_opts(SecondsFormat::Secs, true)),
            session: self.session.as_ref().map(|s| SessionView {
                name: s.session_name.clone(),
                circuit: s.circuit_short_name.clone(),
                start: s.date_start.clone(),
                end: s.date_end.clone(),
            }),
            drivers,
            messages,
            track: self.track.clone(),
        };
        if self.mode == "demo" {
            let now = Utc::now();
            let phase = now.timestamp_millis() as f64 / 60000.0;
            for (i, driver) in snapshot.drivers.iter_mut().enumerate() {
                let point = demo_point((phase - i as f64 * 0.09).rem_euclid(1.0));
                driver.location = Some(DriverLocation {
                    x: point.x,
                    y: point.y,
                    date: now.to_rfc3339(),
                });
            }
        }
        snapshot
    }

    pub fn demo() -> Self {
        let mut state = Self::new("demo");
        state.upstream = "simulated".into();
        let date = Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true);
        state.set_session(Session {
            session_key: 1,
            session_name: "Race · Sample data".into(),
            circuit_short_name: "Demo Grand Prix".into(),
            date_start: date.clone(),
            date_end: date.clone(),
        });
        for (i, (number, name, acronym, team, color)) in [
            (4, "Lando Norris", "NOR", "McLaren", "FF8000"),
            (16, "Charles Leclerc", "LEC", "Ferrari", "E80020"),
            (1, "Max Verstappen", "VER", "Red Bull Racing", "3671C6"),
            (63, "George Russell", "RUS", "Mercedes", "27F4D2"),
        ]
        .into_iter()
        .enumerate()
        {
            let mut apply = |topic: &str, mut fields: Value| {
                fields["session_key"] = json!(1);
                fields["driver_number"] = json!(number);
                fields["date"] = json!(date);
                state.apply(topic, fields);
            };
            apply(
                "drivers",
                json!({"full_name":name,"name_acronym":acronym,"team_name":team,"team_colour":color}),
            );
            apply("position", json!({"position":i+1}));
            apply(
                "intervals",
                json!({"gap_to_leader": if i == 0 { None } else { Some(i as f64 * 2.431) }}),
            );
            apply(
                "laps",
                json!({"lap_number":24,"lap_duration":91.312 + i as f64 * 0.2}),
            );
            apply(
                "stints",
                json!({"stint_number":2,"compound":if i % 2 == 0 {"MEDIUM"} else {"HARD"}}),
            );
        }
        state.apply("race_control", json!({"session_key":1,"date":date,"message":"DEMO — Sample timing. No live race data."}));
        state.track = Some(TrackLayout {
            rotation_degrees: None,
            source: "Fictional demo circuit".into(),
            points: (0..=180)
                .map(|i| demo_point(f64::from(i) / 180.0))
                .collect(),
        });
        state
    }
}

fn demo_point(phase: f64) -> TrackPoint {
    let angle = phase * std::f64::consts::TAU;
    TrackPoint {
        x: 3000.0 * angle.cos() + 750.0 * (3.0 * angle).sin(),
        y: 1800.0 * angle.sin() + 400.0 * (2.0 * angle).cos(),
    }
}
