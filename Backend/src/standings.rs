//! Driver championship standings come from the public Jolpica feed, like the calendar and results;
//! OpenF1 credentials are never involved. The app adds the live projection on top of these official points.
use anyhow::{bail, Context, Result};
use chrono::{Datelike, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex as StdMutex},
    time::{Duration, Instant},
};
use tokio::sync::Mutex;
use tracing::warn;

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

/// What is known about one season. Each season has its own lock, so a slow fetch for one season never
/// blocks another, while concurrent requests for the same season share a single upstream call.
#[derive(Default)]
struct Slot {
    saved: Option<(Standings, Instant)>,
    last_failure: Option<Instant>,
}

pub struct StandingsFeed {
    http: reqwest::Client,
    slots: StdMutex<HashMap<i32, Arc<Mutex<Slot>>>>,
    base_url: String,
    /// How long a fetched table is served without asking the source again.
    ttl: Duration,
    /// How long a failed fetch is remembered before asking again, so an outage is not hammered.
    retry_after: Duration,
}

impl Default for StandingsFeed {
    fn default() -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(15))
                .build()
                .expect("standings HTTP client"),
            slots: StdMutex::new(HashMap::new()),
            base_url: "https://api.jolpi.ca/ergast/f1".into(),
            // Points change when a race is classified, so a short cache keeps a live weekend current.
            ttl: Duration::from_secs(300),
            retry_after: Duration::from_secs(30),
        }
    }
}

pub fn valid_season(year: i32) -> bool {
    (2023..=Utc::now().year() + 1).contains(&year)
}

impl StandingsFeed {
    fn slot(&self, year: i32) -> Arc<Mutex<Slot>> {
        self.slots
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .entry(year)
            .or_default()
            .clone()
    }

    pub async fn load(&self, year: i32, demo: bool) -> Result<Standings> {
        if !valid_season(year) {
            bail!("Unsupported season");
        }
        if demo {
            return Ok(demo_standings(year));
        }
        let slot = self.slot(year);
        let mut slot = slot.lock().await;
        if let Some((saved, at)) = &slot.saved {
            if at.elapsed() < self.ttl {
                return Ok(saved.clone());
            }
        }
        if slot
            .last_failure
            .is_some_and(|at| at.elapsed() < self.retry_after)
        {
            return Self::fallback(&slot, anyhow::anyhow!("Standings source recently failed"));
        }
        match self.fetch(year).await {
            Ok(standings) => {
                slot.saved = Some((standings.clone(), Instant::now()));
                slot.last_failure = None;
                Ok(standings)
            }
            Err(error) => {
                warn!(year, error = %format!("{error:#}"), "Standings refresh failed");
                slot.last_failure = Some(Instant::now());
                Self::fallback(&slot, error)
            }
        }
    }

    /// The last fetched table marked stale, or the error when there is none.
    fn fallback(slot: &Slot, error: anyhow::Error) -> Result<Standings> {
        match &slot.saved {
            Some((saved, _)) => {
                let mut saved = saved.clone();
                saved.stale = true;
                Ok(saved)
            }
            None => Err(error),
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
            retry_after: Duration::ZERO,
            ..StandingsFeed::default()
        };
        assert!(feed.load(2025, false).await.is_err());
        let mut saved = demo_standings(2025);
        saved.mode = "standings".into();
        saved.fetched_at = "2020-01-01T00:00:00Z".into();
        feed.slot(2025).lock().await.saved =
            Some((saved, Instant::now() - Duration::from_secs(3600)));
        let stale = feed.load(2025, false).await.unwrap();
        assert!(stale.stale);
        assert_eq!(feed.load(2025, true).await.unwrap().mode, "demo");
        assert!(feed.load(1900, true).await.is_err());
    }

    use axum::{extract::Path, http::StatusCode, routing::get, Json, Router};
    use std::sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering::SeqCst},
        Arc,
    };

    struct Feed {
        base_url: String,
        requests: Arc<AtomicUsize>,
        failing: Arc<AtomicBool>,
    }

    /// A fake Jolpica: 2024 answers after a pause, everything else at once; `failing` makes it return 500.
    async fn feed() -> Feed {
        let requests = Arc::new(AtomicUsize::new(0));
        let failing = Arc::new(AtomicBool::new(false));
        let (r, f) = (requests.clone(), failing.clone());
        let app = Router::new().route(
            "/{year}/driverStandings/",
            get(move |Path(year): Path<i32>| {
                let (r, f) = (r.clone(), f.clone());
                async move {
                    r.fetch_add(1, SeqCst);
                    if year == 2024 {
                        tokio::time::sleep(Duration::from_millis(600)).await;
                    }
                    if f.load(SeqCst) {
                        return Err(StatusCode::INTERNAL_SERVER_ERROR);
                    }
                    Ok(Json(
                        json!({"MRData":{"total":"1","StandingsTable":{"season":year.to_string(),
                        "round":"3","StandingsLists":[{"season":year.to_string(),"round":"3",
                        "DriverStandings":[row("1","AAA","25","1")]}]}}}),
                    ))
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        Feed {
            base_url,
            requests,
            failing,
        }
    }

    fn client(feed: &Feed, retry_after: Duration) -> StandingsFeed {
        StandingsFeed {
            base_url: feed.base_url.clone(),
            retry_after,
            ..StandingsFeed::default()
        }
    }

    #[tokio::test]
    async fn an_outage_is_not_hammered_but_is_retried_after_the_cooldown() {
        let feed = feed().await;
        feed.failing.store(true, SeqCst);
        let standings = client(&feed, Duration::from_millis(300));
        assert!(standings.load(2025, false).await.is_err());
        assert!(standings.load(2025, false).await.is_err());
        assert!(standings.load(2025, false).await.is_err());
        assert_eq!(
            feed.requests.load(SeqCst),
            1,
            "failures wait out the cooldown"
        );
        feed.failing.store(false, SeqCst);
        tokio::time::sleep(Duration::from_millis(350)).await;
        assert_eq!(standings.load(2025, false).await.unwrap().entries.len(), 1);
        assert_eq!(feed.requests.load(SeqCst), 2);
    }

    #[tokio::test]
    async fn a_slow_season_does_not_block_another() {
        let feed = feed().await;
        let standings = client(&feed, Duration::from_secs(30));
        let slow = standings.load(2024, false);
        let quick = async {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let started = Instant::now();
            standings.load(2025, false).await.unwrap();
            started.elapsed()
        };
        let (slow, quick) = tokio::join!(slow, quick);
        assert!(slow.is_ok());
        assert!(
            quick < Duration::from_millis(300),
            "2025 waited {quick:?} behind the slow 2024 request"
        );
    }
}
