//! Driver championship standings come from the public Jolpica feed, like the calendar and results;
//! OpenF1 credentials are never involved. The app adds the live projection on top of these official points.
use anyhow::{bail, Context, Result};
use chrono::{Datelike, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::HashMap, time::Duration};
use tokio::sync::Mutex;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Standings {
    pub season: i32,
    /// The last round the points include; absent before the season's first race.
    pub round: Option<u32>,
    pub mode: String,
    pub source: String,
    pub fetched_at: String,
    pub stale: bool,
    /// Empty until the source publishes the first standings of the season.
    pub entries: Vec<StandingEntry>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StandingEntry {
    pub position: u32,
    pub code: Option<String>,
    pub name: String,
    pub team: String,
    pub points: f64,
    pub wins: u32,
}

pub struct StandingsFeed {
    http: reqwest::Client,
    cache: Mutex<HashMap<i32, Standings>>,
    base_url: String,
}

impl Default for StandingsFeed {
    fn default() -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(15))
                .build()
                .expect("standings HTTP client"),
            cache: Mutex::new(HashMap::new()),
            base_url: "https://api.jolpi.ca/ergast/f1".into(),
        }
    }
}

pub fn valid_season(year: i32) -> bool {
    (2023..=Utc::now().year() + 1).contains(&year)
}

impl StandingsFeed {
    pub async fn load(&self, year: i32, demo: bool) -> Result<Standings> {
        if !valid_season(year) {
            bail!("Unsupported season");
        }
        if demo {
            return Ok(demo_standings(year));
        }
        let mut cache = self.cache.lock().await;
        // Points change when a race is classified, so a short cache keeps a live weekend current.
        if let Some(saved) = cache.get(&year) {
            let age = chrono::DateTime::parse_from_rfc3339(&saved.fetched_at)?;
            if Utc::now().signed_duration_since(age).num_seconds() < 300 {
                return Ok(saved.clone());
            }
        }
        match self.fetch(year).await {
            Ok(standings) => {
                cache.insert(year, standings.clone());
                Ok(standings)
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

    async fn fetch(&self, year: i32) -> Result<Standings> {
        let value: Value = self
            .http
            .get(format!("{}/{year}/driverStandings/", self.base_url))
            .query(&[("limit", "100")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        normalize(year, &value)
    }
}

fn normalize(year: i32, value: &Value) -> Result<Standings> {
    let lists = value["MRData"]["StandingsTable"]["StandingsLists"]
        .as_array()
        .context("Missing standings")?;
    let total: usize = value["MRData"]["total"]
        .as_str()
        .context("Missing standings total")?
        .parse()?;
    let mut round = None;
    let mut entries = Vec::new();
    if let Some(list) = lists.first() {
        if lists.len() != 1
            || list["season"].as_str().and_then(|s| s.parse::<i32>().ok()) != Some(year)
        {
            bail!("Unexpected season in standings");
        }
        round = list["round"].as_str().and_then(|s| s.parse::<u32>().ok());
        let records = list["DriverStandings"]
            .as_array()
            .context("Missing driver standings")?;
        if records.len() != total {
            bail!("Incomplete standings response");
        }
        for record in records {
            entries.push(entry(record)?);
        }
        entries.sort_by_key(|entry| entry.position);
    } else if total != 0 {
        bail!("Incomplete standings response");
    }
    Ok(Standings {
        season: year,
        round,
        mode: "standings".into(),
        source: "Jolpica F1".into(),
        fetched_at: Utc::now().to_rfc3339(),
        stale: false,
        entries,
    })
}

fn entry(record: &Value) -> Result<StandingEntry> {
    let text = |value: &Value| -> Result<String> {
        Ok(value
            .as_str()
            .context("Missing standings field")?
            .to_owned())
    };
    let driver = &record["Driver"];
    Ok(StandingEntry {
        position: record["position"]
            .as_str()
            .and_then(|s| s.parse().ok())
            .context("Missing standings position")?,
        code: driver["code"].as_str().map(str::to_owned),
        name: format!(
            "{} {}",
            text(&driver["givenName"])?,
            text(&driver["familyName"])?
        ),
        // A driver who changed team lists the latest first.
        team: text(&record["Constructors"][0]["name"])?,
        points: text(&record["points"])?.parse()?,
        wins: text(&record["wins"])?.parse()?,
    })
}

/// Fictional points for the four demo-timing drivers, so the live projection can be tried without a race.
fn demo_standings(year: i32) -> Standings {
    let entry =
        |position: u32, code: &str, name: &str, team: &str, points: f64, wins: u32| StandingEntry {
            position,
            code: Some(code.into()),
            name: name.into(),
            team: team.into(),
            points,
            wins,
        };
    Standings {
        season: year,
        round: Some(10),
        mode: "demo".into(),
        source: "Fictional sample standings".into(),
        fetched_at: Utc::now().to_rfc3339(),
        stale: false,
        entries: vec![
            entry(1, "VER", "Max Verstappen", "Red Bull Racing", 180.0, 4),
            entry(2, "NOR", "Lando Norris", "McLaren", 172.0, 3),
            entry(3, "LEC", "Charles Leclerc", "Ferrari", 150.0, 2),
            entry(4, "RUS", "George Russell", "Mercedes", 141.0, 1),
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn table(entries: Value, total: &str) -> Value {
        json!({"MRData":{"total":total,"StandingsTable":{"season":"2025","round":"24",
            "StandingsLists":[{"season":"2025","round":"24","DriverStandings":entries}]}}})
    }

    fn row(position: &str, code: &str, points: &str, wins: &str) -> Value {
        json!({"position":position,"points":points,"wins":wins,
            "Driver":{"code":code,"givenName":"Given","familyName":code},
            "Constructors":[{"name":"Latest Team"},{"name":"First Team"}]})
    }

    #[test]
    fn normalizes_order_points_wins_and_latest_team() {
        let value = table(
            json!([row("2", "VER", "421", "8"), row("1", "NOR", "423.5", "7")]),
            "2",
        );
        let standings = normalize(2025, &value).unwrap();
        assert_eq!(standings.round, Some(24));
        let codes: Vec<_> = standings
            .entries
            .iter()
            .map(|e| e.code.clone().unwrap())
            .collect();
        assert_eq!(codes, ["NOR", "VER"]);
        assert_eq!(standings.entries[0].points, 423.5);
        assert_eq!(standings.entries[1].wins, 8);
        assert_eq!(standings.entries[0].team, "Latest Team");
        assert_eq!(standings.mode, "standings");
    }

    #[test]
    fn season_without_standings_is_empty_but_mismatches_are_errors() {
        let none = json!({"MRData":{"total":"0","StandingsTable":{"season":"2027","round":null,"StandingsLists":[]}}});
        let empty = normalize(2027, &none).unwrap();
        assert!(empty.entries.is_empty() && empty.round.is_none());
        assert!(
            normalize(2025, &table(json!([]), "1")).is_err(),
            "truncated response"
        );
        assert!(
            normalize(2024, &table(json!([]), "0")).is_err(),
            "wrong season"
        );
        let truncated = json!({"MRData":{"total":"3","StandingsTable":{"StandingsLists":[]}}});
        assert!(normalize(2025, &truncated).is_err());
    }

    #[test]
    fn shared_swift_fixture_preserves_wire_contract() {
        let raw = include_str!("../../Tests/Fixtures/standings.json");
        let standings: Standings = serde_json::from_str(raw).unwrap();
        let encoded = serde_json::to_value(standings).unwrap();
        assert_eq!(encoded, serde_json::from_str::<Value>(raw).unwrap());
    }

    #[tokio::test]
    async fn stale_cache_survives_failure_and_demo_never_calls_upstream() {
        let feed = StandingsFeed {
            base_url: "http://127.0.0.1:0".into(),
            ..StandingsFeed::default()
        };
        assert!(feed.load(2025, false).await.is_err());
        let mut saved = demo_standings(2025);
        saved.mode = "standings".into();
        saved.fetched_at = "2020-01-01T00:00:00Z".into();
        feed.cache.lock().await.insert(2025, saved);
        let stale = feed.load(2025, false).await.unwrap();
        assert!(stale.stale);
        assert_eq!(feed.load(2025, true).await.unwrap().mode, "demo");
        assert!(feed.load(1900, true).await.is_err());
    }
}
