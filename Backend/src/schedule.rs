//! Calendar data is independent of the paid OpenF1 timing connection.
use anyhow::{bail, Context, Result};
use chrono::{Datelike, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::HashMap, time::Duration};
use tokio::sync::Mutex;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Schedule {
    pub season: i32,
    pub mode: String,
    pub source: String,
    pub fetched_at: String,
    pub stale: bool,
    pub races: Vec<Weekend>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Weekend {
    pub round: u32,
    pub name: String,
    pub circuit: String,
    pub country: String,
    pub sessions: Vec<Session>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub name: String,
    /// Calendar date from the source; never turn an unknown time into midnight UTC.
    pub date: String,
    pub start: Option<String>,
}

pub struct Calendar {
    http: reqwest::Client,
    // Serializes refreshes, so multiple clients do not burst the public API.
    cache: Mutex<HashMap<i32, Schedule>>,
    base_url: String,
}

impl Default for Calendar {
    fn default() -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(15))
                .build()
                .expect("calendar HTTP client"),
            cache: Mutex::new(HashMap::new()),
            base_url: "https://api.jolpi.ca/ergast/f1".into(),
        }
    }
}

impl Calendar {
    pub async fn load(&self, year: i32, demo: bool) -> Result<Schedule> {
        if !(2023..=Utc::now().year() + 1).contains(&year) {
            bail!("Unsupported season");
        }
        if demo {
            return Ok(demo_schedule(year));
        }
        let mut cache = self.cache.lock().await;
        if let Some(saved) = cache.get(&year) {
            let age = chrono::DateTime::parse_from_rfc3339(&saved.fetched_at)?;
            if Utc::now().signed_duration_since(age).num_seconds() < 900 {
                return Ok(saved.clone());
            }
        }
        match self.fetch(year).await {
            Ok(schedule) => {
                cache.insert(year, schedule.clone());
                Ok(schedule)
            }
            Err(error) => match cache.get(&year) {
                Some(saved) => {
                    let mut saved = saved.clone();
                    saved.stale = true;
                    Ok(saved)
                }
                None => Err(error),
            },
        }
    }

    async fn fetch(&self, year: i32) -> Result<Schedule> {
        let value: Value = self
            .http
            .get(format!("{}/{year}/races/", self.base_url))
            .query(&[("limit", "100")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        normalize(year, &value)
    }
}

fn normalize(year: i32, value: &Value) -> Result<Schedule> {
    let records = value["MRData"]["RaceTable"]["Races"]
        .as_array()
        .context("Missing calendar races")?;
    let total: usize = value["MRData"]["total"]
        .as_str()
        .context("Missing calendar total")?
        .parse()?;
    if total != records.len() {
        bail!("Incomplete calendar response");
    }
    let mut races = Vec::new();
    for race in records {
        let text = |value: &Value| -> Result<String> {
            Ok(value.as_str().context("Missing calendar field")?.to_owned())
        };
        if race["season"].as_str().and_then(|s| s.parse::<i32>().ok()) != Some(year) {
            bail!("Unexpected calendar season");
        }
        let mut sessions = Vec::new();
        for (key, name) in [
            ("FirstPractice", "Practice 1"),
            ("SecondPractice", "Practice 2"),
            ("ThirdPractice", "Practice 3"),
            ("SprintQualifying", "Sprint qualifying"),
            ("SprintShootout", "Sprint qualifying"),
            ("Sprint", "Sprint"),
            ("Qualifying", "Qualifying"),
            ("", "Race"),
        ] {
            let record = if key.is_empty() { race } else { &race[key] };
            if record.is_null() {
                continue;
            }
            // Some feeds may expose both names for the 2023 sprint shootout.
            if sessions.iter().any(|s: &Session| s.name == name) {
                continue;
            }
            let date = text(&record["date"])?;
            chrono::NaiveDate::parse_from_str(&date, "%Y-%m-%d")?;
            let start = record["time"].as_str().map(|time| format!("{date}T{time}"));
            if let Some(start) = &start {
                chrono::DateTime::parse_from_rfc3339(start)?;
            }
            sessions.push(Session {
                name: name.into(),
                date,
                start,
            });
        }
        sessions.sort_by(|a, b| a.date.cmp(&b.date).then(a.start.cmp(&b.start)));
        races.push(Weekend {
            round: text(&race["round"])?.parse()?,
            name: text(&race["raceName"])?,
            circuit: text(&race["Circuit"]["circuitName"])?,
            country: text(&race["Circuit"]["Location"]["country"])?,
            sessions,
        });
    }
    races.sort_by_key(|race| race.round);
    Ok(Schedule {
        season: year,
        mode: "calendar".into(),
        source: "Jolpica F1".into(),
        fetched_at: Utc::now().to_rfc3339(),
        stale: false,
        races,
    })
}

fn demo_schedule(year: i32) -> Schedule {
    let weekend = |round, name: &str, month, sprint| {
        let day = 10;
        let mut sessions = vec![Session {
            name: "Practice 1".into(),
            date: format!("{year}-{month:02}-{day:02}"),
            start: Some(format!("{year}-{month:02}-{day:02}T12:00:00Z")),
        }];
        let kinds = if sprint {
            vec![
                ("Sprint qualifying", 10, 16),
                ("Sprint", 11, 12),
                ("Qualifying", 11, 16),
            ]
        } else {
            vec![
                ("Practice 2", 10, 16),
                ("Practice 3", 11, 12),
                ("Qualifying", 11, 16),
            ]
        };
        for (name, day, hour) in kinds.into_iter().chain([("Race", 12, 14)]) {
            sessions.push(Session {
                name: name.into(),
                date: format!("{year}-{month:02}-{day:02}"),
                start: Some(format!("{year}-{month:02}-{day:02}T{hour:02}:00:00Z")),
            });
        }
        Weekend {
            round,
            name: name.into(),
            circuit: "Sample circuit".into(),
            country: "Demo".into(),
            sessions,
        }
    };
    Schedule {
        season: year,
        mode: "demo".into(),
        source: "Fictional sample calendar".into(),
        fetched_at: Utc::now().to_rfc3339(),
        stale: false,
        races: vec![
            weekend(1, "Sample Grand Prix", 3, false),
            weekend(2, "Sample Sprint Weekend", 11, true),
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn shared_swift_fixture_preserves_wire_contract() {
        let raw = include_str!("../../Tests/Fixtures/schedule.json");
        let schedule: Schedule = serde_json::from_str(raw).unwrap();
        let encoded = serde_json::to_value(schedule).unwrap();
        assert_eq!(encoded, serde_json::from_str::<Value>(raw).unwrap());
        assert_eq!(
            encoded["races"][1]["sessions"][1]["name"],
            "Sprint qualifying"
        );
    }

    #[test]
    fn preserves_all_sprint_sessions_and_unknown_times() {
        let value = json!({"MRData":{"total":"1","RaceTable":{"Races":[{
            "season":"2026","round":"2","raceName":"Chinese Grand Prix",
            "Circuit":{"circuitName":"Shanghai","Location":{"country":"China"}},
            "date":"2026-03-15","time":"07:00:00Z",
            "FirstPractice":{"date":"2026-03-13","time":"03:30:00Z"},
            "SprintQualifying":{"date":"2026-03-13","time":"07:30:00Z"},
            "Sprint":{"date":"2026-03-14","time":"03:00:00Z"},
            "Qualifying":{"date":"2026-03-14"}
        }]}}});
        let schedule = normalize(2026, &value).unwrap();
        let sessions = &schedule.races[0].sessions;
        assert_eq!(
            sessions.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(),
            [
                "Practice 1",
                "Sprint qualifying",
                "Qualifying",
                "Sprint",
                "Race"
            ]
        );
        assert_eq!(sessions[1].start.as_deref(), Some("2026-03-13T07:30:00Z"));
        assert!(sessions[2].start.is_none());
        assert_eq!(sessions[2].date, "2026-03-14");
        assert!(normalize(2025, &value).is_err());
        let mut partial = value;
        partial["MRData"]["total"] = json!("2");
        assert!(normalize(2026, &partial).is_err());
    }

    #[tokio::test]
    async fn stale_cache_survives_upstream_failure_and_demo_never_calls_upstream() {
        let calendar = Calendar {
            base_url: "http://127.0.0.1:0".into(),
            ..Calendar::default()
        };
        assert!(calendar.load(2026, false).await.is_err());
        let mut saved = demo_schedule(2026);
        saved.mode = "calendar".into();
        saved.fetched_at = "2020-01-01T00:00:00Z".into();
        calendar.cache.lock().await.insert(2026, saved);
        let stale = calendar.load(2026, false).await.unwrap();
        assert!(stale.stale);
        assert_eq!(stale.fetched_at, "2020-01-01T00:00:00Z");
        assert_eq!(calendar.load(2026, true).await.unwrap().mode, "demo");
        assert!(calendar.load(1900, true).await.is_err());
    }
}
