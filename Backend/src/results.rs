//! Race results come from the public Jolpica feed, like the calendar; OpenF1 credentials are never involved.
use anyhow::{bail, Context, Result};
use chrono::{Datelike, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::HashMap, time::Duration};
use tokio::sync::Mutex;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaceResults {
    pub season: i32,
    pub round: u32,
    pub mode: String,
    pub source: String,
    pub fetched_at: String,
    pub stale: bool,
    /// Empty while the source has not published the classification yet.
    pub entries: Vec<ResultEntry>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResultEntry {
    pub position: u32,
    /// "1", "2" ... or "R", "D", "W" for drivers who were not classified.
    pub position_text: String,
    pub code: Option<String>,
    pub name: String,
    pub team: String,
    pub grid: Option<u32>,
    pub laps: Option<u32>,
    /// Race time for the winner, gap to the winner for the rest; absent for lapped and retired drivers.
    pub time: Option<String>,
    pub status: String,
    pub points: f64,
    pub fastest_lap: bool,
}

pub struct Results {
    http: reqwest::Client,
    cache: Mutex<HashMap<(i32, u32), RaceResults>>,
    base_url: String,
}

impl Default for Results {
    fn default() -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(15))
                .build()
                .expect("results HTTP client"),
            cache: Mutex::new(HashMap::new()),
            base_url: "https://api.jolpi.ca/ergast/f1".into(),
        }
    }
}

pub fn valid_race(year: i32, round: u32) -> bool {
    (2023..=Utc::now().year() + 1).contains(&year) && (1..=30).contains(&round)
}

impl Results {
    pub async fn load(&self, year: i32, round: u32, demo: bool) -> Result<RaceResults> {
        if !valid_race(year, round) {
            bail!("Unsupported race");
        }
        if demo {
            return Ok(demo_results(year, round));
        }
        let mut cache = self.cache.lock().await;
        if let Some(saved) = cache.get(&(year, round)) {
            let age = chrono::DateTime::parse_from_rfc3339(&saved.fetched_at)?;
            if Utc::now().signed_duration_since(age).num_seconds() < 900 {
                return Ok(saved.clone());
            }
        }
        match self.fetch(year, round).await {
            Ok(results) => {
                // An unpublished classification is not cached, so it appears as soon as the source has it.
                if !results.entries.is_empty() {
                    cache.insert((year, round), results.clone());
                }
                Ok(results)
            }
            Err(error) => match cache.get(&(year, round)) {
                Some(saved) => {
                    let mut saved = saved.clone();
                    saved.stale = true;
                    Ok(saved)
                }
                None => Err(error),
            },
        }
    }

    async fn fetch(&self, year: i32, round: u32) -> Result<RaceResults> {
        let value: Value = self
            .http
            .get(format!("{}/{year}/{round}/results/", self.base_url))
            .query(&[("limit", "100")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        normalize(year, round, &value)
    }
}

fn normalize(year: i32, round: u32, value: &Value) -> Result<RaceResults> {
    let races = value["MRData"]["RaceTable"]["Races"]
        .as_array()
        .context("Missing race results")?;
    let total: usize = value["MRData"]["total"]
        .as_str()
        .context("Missing results total")?
        .parse()?;
    let mut entries = Vec::new();
    if let Some(race) = races.first() {
        if races.len() != 1
            || race["season"].as_str().and_then(|s| s.parse::<i32>().ok()) != Some(year)
            || race["round"].as_str().and_then(|s| s.parse::<u32>().ok()) != Some(round)
        {
            bail!("Unexpected race in results");
        }
        let records = race["Results"].as_array().context("Missing results")?;
        if records.len() != total {
            bail!("Incomplete results response");
        }
        for record in records {
            entries.push(entry(record)?);
        }
        entries.sort_by_key(|entry| entry.position);
    } else if total != 0 {
        bail!("Incomplete results response");
    }
    Ok(RaceResults {
        season: year,
        round,
        mode: "results".into(),
        source: "Jolpica F1".into(),
        fetched_at: Utc::now().to_rfc3339(),
        stale: false,
        entries,
    })
}

fn entry(record: &Value) -> Result<ResultEntry> {
    let text = |value: &Value| -> Result<String> {
        Ok(value.as_str().context("Missing result field")?.to_owned())
    };
    let number = |value: &Value| value.as_str().and_then(|s| s.parse::<u32>().ok());
    let driver = &record["Driver"];
    Ok(ResultEntry {
        position: number(&record["position"]).context("Missing result position")?,
        position_text: text(&record["positionText"])?,
        code: driver["code"].as_str().map(str::to_owned),
        name: format!(
            "{} {}",
            text(&driver["givenName"])?,
            text(&driver["familyName"])?
        ),
        team: text(&record["Constructor"]["name"])?,
        // A pit-lane start is reported as grid 0; it is not a pole position.
        grid: number(&record["grid"]).filter(|grid| *grid > 0),
        laps: number(&record["laps"]),
        time: record["Time"]["time"].as_str().map(str::to_owned),
        status: text(&record["status"])?,
        points: text(&record["points"])?.parse()?,
        fastest_lap: record["FastestLap"]["rank"].as_str() == Some("1"),
    })
}

fn demo_results(year: i32, round: u32) -> RaceResults {
    let entry =
        |position: u32, code: &str, name: &str, team: &str, time: &str, points: f64| ResultEntry {
            position,
            position_text: position.to_string(),
            code: Some(code.into()),
            name: name.into(),
            team: team.into(),
            grid: Some(position),
            laps: Some(57),
            time: Some(time.into()),
            status: "Finished".into(),
            points,
            fastest_lap: position == 2,
        };
    RaceResults {
        season: year,
        round,
        mode: "demo".into(),
        source: "Fictional sample results".into(),
        fetched_at: Utc::now().to_rfc3339(),
        stale: false,
        entries: vec![
            entry(
                1,
                "AAA",
                "Alex Sample",
                "Sample Racing",
                "1:30:00.000",
                25.0,
            ),
            entry(2, "BBB", "Blake Example", "Example GP", "+4.200", 18.0),
            entry(3, "CCC", "Casey Demo", "Demo Motorsport", "+9.800", 15.0),
            ResultEntry {
                position: 4,
                position_text: "R".into(),
                time: None,
                laps: Some(31),
                status: "Retired".into(),
                points: 0.0,
                fastest_lap: false,
                ..entry(4, "DDD", "Drew Placeholder", "Sample Racing", "", 0.0)
            },
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn race(results: Value, total: &str) -> Value {
        json!({"MRData":{"total":total,"RaceTable":{"Races":[{
            "season":"2025","round":"1","Results":results}]}}})
    }

    #[test]
    fn shared_swift_fixture_preserves_wire_contract() {
        let raw = include_str!("../../Tests/Fixtures/results.json");
        let results: RaceResults = serde_json::from_str(raw).unwrap();
        let encoded = serde_json::to_value(results).unwrap();
        assert_eq!(encoded, serde_json::from_str::<Value>(raw).unwrap());
    }

    #[test]
    fn normalizes_winner_gap_lapped_retired_and_fastest_lap() {
        let value = race(
            json!([
                {"position":"2","positionText":"2","points":"18","grid":"3","laps":"57","status":"Finished",
                 "Driver":{"code":"VER","givenName":"Max","familyName":"Verstappen"},
                 "Constructor":{"name":"Red Bull"},"Time":{"time":"+0.895"},
                 "FastestLap":{"rank":"3"}},
                {"position":"1","positionText":"1","points":"26","grid":"1","laps":"57","status":"Finished",
                 "Driver":{"code":"NOR","givenName":"Lando","familyName":"Norris"},
                 "Constructor":{"name":"McLaren"},"Time":{"time":"1:42:06.304"},
                 "FastestLap":{"rank":"1"}},
                {"position":"19","positionText":"R","points":"0","grid":"0","laps":"0","status":"Retired",
                 "Driver":{"givenName":"Jack","familyName":"Doohan"},
                 "Constructor":{"name":"Alpine F1 Team"}},
                {"position":"15","positionText":"15","points":"0.5","grid":"14","laps":"56","status":"+1 Lap",
                 "Driver":{"code":"SAI","givenName":"Carlos","familyName":"Sainz"},
                 "Constructor":{"name":"Williams"}}
            ]),
            "4",
        );
        let results = normalize(2025, 1, &value).unwrap();
        let positions: Vec<_> = results.entries.iter().map(|e| e.position).collect();
        assert_eq!(positions, [1, 2, 15, 19]);
        let winner = &results.entries[0];
        assert_eq!(winner.name, "Lando Norris");
        assert_eq!(winner.time.as_deref(), Some("1:42:06.304"));
        assert!(winner.fastest_lap);
        assert!(!results.entries[1].fastest_lap);
        assert_eq!(results.entries[2].points, 0.5);
        assert_eq!(results.entries[2].status, "+1 Lap");
        assert!(results.entries[2].time.is_none());
        let retired = &results.entries[3];
        assert_eq!(retired.position_text, "R");
        assert!(retired.code.is_none());
        assert!(retired.grid.is_none(), "pit-lane start is not grid 0");
        assert_eq!(results.mode, "results");
    }

    #[test]
    fn unpublished_results_are_empty_but_mismatches_are_errors() {
        let none = json!({"MRData":{"total":"0","RaceTable":{"Races":[]}}});
        assert!(normalize(2025, 1, &none).unwrap().entries.is_empty());
        let value = race(json!([]), "1");
        assert!(normalize(2025, 1, &value).is_err(), "truncated response");
        let value = race(json!([]), "0");
        assert!(normalize(2025, 2, &value).is_err(), "wrong round");
        assert!(normalize(2024, 1, &value).is_err(), "wrong season");
        let truncated = json!({"MRData":{"total":"3","RaceTable":{"Races":[]}}});
        assert!(normalize(2025, 1, &truncated).is_err());
    }

    #[tokio::test]
    async fn stale_cache_survives_failure_and_demo_never_calls_upstream() {
        let results = Results {
            base_url: "http://127.0.0.1:0".into(),
            ..Results::default()
        };
        assert!(results.load(2025, 1, false).await.is_err());
        let mut saved = demo_results(2025, 1);
        saved.mode = "results".into();
        saved.fetched_at = "2020-01-01T00:00:00Z".into();
        results.cache.lock().await.insert((2025, 1), saved);
        let stale = results.load(2025, 1, false).await.unwrap();
        assert!(stale.stale);
        assert_eq!(stale.fetched_at, "2020-01-01T00:00:00Z");
        assert_eq!(results.load(2025, 1, true).await.unwrap().mode, "demo");
        assert!(results.load(1900, 1, true).await.is_err());
        assert!(results.load(2025, 0, true).await.is_err());
    }
}
