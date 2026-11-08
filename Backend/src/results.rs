//! Race results come from the public Jolpica feed, like the calendar; OpenF1 credentials are never involved.
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
    /// How many times the car stopped in the pits. Absent when the source has no pit-stop data for the
    /// race, which is different from a car that never stopped.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pit_stops: Option<u32>,
}

/// What is known about one race. Each race has its own lock, so a slow fetch for one race never blocks
/// another, while concurrent requests for the same race share a single upstream call.
#[derive(Default)]
struct Slot {
    saved: Option<(RaceResults, Instant)>,
    last_failure: Option<Instant>,
}

type Slots = StdMutex<HashMap<(i32, u32), Arc<Mutex<Slot>>>>;

pub struct Results {
    http: reqwest::Client,
    slots: Slots,
    base_url: String,
    /// How long a published classification is served without asking the source again.
    ttl: Duration,
    /// How long an unpublished classification, or a failed fetch, is remembered before asking again.
    retry_after: Duration,
}

impl Default for Results {
    fn default() -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(15))
                .build()
                .expect("results HTTP client"),
            slots: StdMutex::new(HashMap::new()),
            base_url: "https://api.jolpi.ca/ergast/f1".into(),
            ttl: Duration::from_secs(900),
            retry_after: Duration::from_secs(30),
        }
    }
}

pub fn valid_race(year: i32, round: u32) -> bool {
    (2023..=Utc::now().year() + 1).contains(&year) && (1..=30).contains(&round)
}

impl Results {
    fn slot(&self, year: i32, round: u32) -> Arc<Mutex<Slot>> {
        self.slots
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .entry((year, round))
            .or_default()
            .clone()
    }

    pub async fn load(&self, year: i32, round: u32, demo: bool) -> Result<RaceResults> {
        if !valid_race(year, round) {
            bail!("Unsupported race");
        }
        if demo {
            return Ok(demo_results(year, round));
        }
        let slot = self.slot(year, round);
        let mut slot = slot.lock().await;
        if let Some((saved, at)) = &slot.saved {
            // A classification that is not published yet is re-checked sooner than a published one.
            let ttl = if saved.entries.is_empty() {
                self.retry_after
            } else {
                self.ttl
            };
            if at.elapsed() < ttl {
                return Ok(saved.clone());
            }
        }
        if slot
            .last_failure
            .is_some_and(|at| at.elapsed() < self.retry_after)
        {
            return Self::fallback(&slot, anyhow::anyhow!("Results source recently failed"));
        }
        match self.fetch(year, round).await {
            Ok(results) => {
                slot.saved = Some((results.clone(), Instant::now()));
                slot.last_failure = None;
                Ok(results)
            }
            Err(error) => {
                warn!(year, round, error = %format!("{error:#}"), "Race results refresh failed");
                slot.last_failure = Some(Instant::now());
                Self::fallback(&slot, error)
            }
        }
    }

    /// The last published classification marked stale, or the error when there is none.
    fn fallback(slot: &Slot, error: anyhow::Error) -> Result<RaceResults> {
        match &slot.saved {
            Some((saved, _)) if !saved.entries.is_empty() => {
                let mut saved = saved.clone();
                saved.stale = true;
                Ok(saved)
            }
            _ => Err(error),
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
        let mut results = normalize(year, round, &value, None)?;
        // Pit stops are a nice-to-have: without them the classification is still worth showing.
        if !results.entries.is_empty() {
            match self.fetch_pit_stops(year, round).await {
                Ok(stops) => results = normalize(year, round, &value, stops.as_ref())?,
                Err(error) => {
                    warn!(year, round, error = %format!("{error:#}"), "Pit stops refresh failed");
                }
            }
        }
        Ok(results)
    }

    /// Pit stops per Jolpica `driverId`, or None while the source has published none for the race.
    async fn fetch_pit_stops(&self, year: i32, round: u32) -> Result<Option<HashMap<String, u32>>> {
        const PAGE: usize = 100;
        // A race has a few dozen stops; the cap only stops a misbehaving source from looping forever.
        const MAX_PAGES: usize = 10;
        let mut stops: HashMap<String, u32> = HashMap::new();
        let mut seen = 0;
        for page in 0..MAX_PAGES {
            let value: Value = self
                .http
                .get(format!("{}/{year}/{round}/pitstops/", self.base_url))
                .query(&[
                    ("limit", PAGE.to_string()),
                    ("offset", (page * PAGE).to_string()),
                ])
                .send()
                .await?
                .error_for_status()?
                .json()
                .await?;
            let total: usize = value["MRData"]["total"]
                .as_str()
                .context("Missing pit stops total")?
                .parse()?;
            if total == 0 {
                return Ok(None);
            }
            let race = value["MRData"]["RaceTable"]["Races"]
                .as_array()
                .and_then(|races| races.first())
                .context("Missing pit stops race")?;
            if race["season"].as_str().and_then(|s| s.parse::<i32>().ok()) != Some(year)
                || race["round"].as_str().and_then(|s| s.parse::<u32>().ok()) != Some(round)
            {
                bail!("Unexpected race in pit stops");
            }
            let records = race["PitStops"].as_array().context("Missing pit stops")?;
            for record in records {
                if let Some(driver) = record["driverId"].as_str() {
                    *stops.entry(driver.to_owned()).or_default() += 1;
                }
            }
            seen += records.len();
            if seen >= total {
                return Ok(Some(stops));
            }
            if records.is_empty() {
                break;
            }
        }
        bail!("Incomplete pit stops response")
    }
}

/// `pit_stops` counts stops per Jolpica `driverId`. When it is present, a driver it does not list never
/// stopped; when it is absent, the number of stops is unknown.
fn normalize(
    year: i32,
    round: u32,
    value: &Value,
    pit_stops: Option<&HashMap<String, u32>>,
) -> Result<RaceResults> {
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
            entries.push(entry(record, pit_stops)?);
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

fn entry(record: &Value, pit_stops: Option<&HashMap<String, u32>>) -> Result<ResultEntry> {
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
        pit_stops: pit_stops.map(|stops| {
            driver["driverId"]
                .as_str()
                .and_then(|id| stops.get(id).copied())
                .unwrap_or(0)
        }),
    })
}

fn demo_results(year: i32, round: u32) -> RaceResults {
    let entry =
        |position: u32, code: &str, name: &str, team: &str, time: &str, points: f64| ResultEntry {
            pit_stops: Some(if position % 2 == 0 { 2 } else { 1 }),
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
        let results = normalize(2025, 1, &value, None).unwrap();
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
    fn pit_stops_are_counted_per_driver_and_unknown_without_data() {
        let value = race(
            json!([
                {"position":"1","positionText":"1","points":"25","grid":"1","laps":"57","status":"Finished",
                 "Driver":{"driverId":"norris","code":"NOR","givenName":"Lando","familyName":"Norris"},
                 "Constructor":{"name":"McLaren"},"Time":{"time":"1:42:06.304"}},
                {"position":"2","positionText":"R","points":"0","grid":"2","laps":"0","status":"Retired",
                 "Driver":{"driverId":"max_verstappen","givenName":"Max","familyName":"Verstappen"},
                 "Constructor":{"name":"Red Bull"}}
            ]),
            "2",
        );
        let stops = HashMap::from([("norris".to_owned(), 2)]);
        let known = normalize(2025, 1, &value, Some(&stops)).unwrap();
        assert_eq!(known.entries[0].pit_stops, Some(2));
        assert_eq!(
            known.entries[1].pit_stops,
            Some(0),
            "listed data, no stops: never stopped"
        );
        let unknown = normalize(2025, 1, &value, None).unwrap();
        assert!(unknown.entries.iter().all(|e| e.pit_stops.is_none()));
        let wire = serde_json::to_value(&unknown.entries[0]).unwrap();
        assert!(
            wire.get("pitStops").is_none(),
            "unknown stops are left off the wire"
        );
    }

    #[test]
    fn unpublished_results_are_empty_but_mismatches_are_errors() {
        let none = json!({"MRData":{"total":"0","RaceTable":{"Races":[]}}});
        assert!(normalize(2025, 1, &none, None).unwrap().entries.is_empty());
        let value = race(json!([]), "1");
        assert!(
            normalize(2025, 1, &value, None).is_err(),
            "truncated response"
        );
        let value = race(json!([]), "0");
        assert!(normalize(2025, 2, &value, None).is_err(), "wrong round");
        assert!(normalize(2024, 1, &value, None).is_err(), "wrong season");
        let truncated = json!({"MRData":{"total":"3","RaceTable":{"Races":[]}}});
        assert!(normalize(2025, 1, &truncated, None).is_err());
    }

    /// A stand-in for the Jolpica feed that counts requests and can answer slowly, with errors, or empty.
    struct Feed {
        base_url: String,
        requests: Arc<std::sync::atomic::AtomicUsize>,
        published: Arc<std::sync::atomic::AtomicBool>,
        failing: Arc<std::sync::atomic::AtomicBool>,
    }

    async fn feed(slow_round: Option<u32>) -> Feed {
        use axum::{extract::Path, routing::get, Json, Router};
        use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering::SeqCst};
        let requests = Arc::new(AtomicUsize::new(0));
        let published = Arc::new(AtomicBool::new(false));
        let failing = Arc::new(AtomicBool::new(false));
        let (r, p, f) = (requests.clone(), published.clone(), failing.clone());
        let app = Router::new().route(
            "/{year}/{round}/pitstops/",
            get(|Path((year, round)): Path<(i32, u32)>| async move {
                // Round 3 has no pit-stop data yet; round 4's feed is broken; the rest stopped twice.
                match round {
                    4 => Err(axum::http::StatusCode::INTERNAL_SERVER_ERROR),
                    3 => Ok(Json(json!({"MRData":{"total":"0","RaceTable":{"Races":[]}}}))),
                    _ => Ok(Json(json!({"MRData":{"total":"2","RaceTable":{"Races":[{
                        "season":year.to_string(),"round":round.to_string(),
                        "PitStops":[{"driverId":"aaa","stop":"1","lap":"20"},
                                    {"driverId":"aaa","stop":"2","lap":"41"}]}]}}}))),
                }
            }),
        )
        .route(
            "/{year}/{round}/results/",
            get(move |Path((year, round)): Path<(i32, u32)>| {
                let (r, p, f) = (r.clone(), p.clone(), f.clone());
                async move {
                    r.fetch_add(1, SeqCst);
                    if slow_round == Some(round) {
                        tokio::time::sleep(Duration::from_millis(1500)).await;
                    }
                    if f.load(SeqCst) {
                        return Err(axum::http::StatusCode::INTERNAL_SERVER_ERROR);
                    }
                    let record = json!({"position":"1","positionText":"1","points":"25","grid":"1","laps":"57",
                        "status":"Finished","Driver":{"driverId":"aaa","code":"AAA","givenName":"Alex","familyName":"Sample"},
                        "Constructor":{"name":"Team"},"Time":{"time":"1:30:00.000"}});
                    let (races, total) = if p.load(SeqCst) {
                        (json!([{"season":year.to_string(),"round":round.to_string(),"Results":[record]}]), "1")
                    } else {
                        (json!([]), "0")
                    };
                    Ok(Json(json!({"MRData":{"total":total,"RaceTable":{"Races":races}}})))
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        Feed {
            base_url,
            requests,
            published,
            failing,
        }
    }

    fn client(feed: &Feed, retry_after: Duration) -> Results {
        Results {
            base_url: feed.base_url.clone(),
            retry_after,
            ..Results::default()
        }
    }

    fn count(feed: &Feed) -> usize {
        feed.requests.load(std::sync::atomic::Ordering::SeqCst)
    }

    #[tokio::test]
    async fn unpublished_classification_is_asked_for_once_then_picked_up_later() {
        let feed = feed(None).await;
        let results = client(&feed, Duration::from_millis(300));
        let (a, b, c) = tokio::join!(
            results.load(2025, 1, false),
            results.load(2025, 1, false),
            results.load(2025, 1, false)
        );
        assert!(
            a.unwrap().entries.is_empty()
                && b.unwrap().entries.is_empty()
                && c.unwrap().entries.is_empty()
        );
        assert_eq!(count(&feed), 1, "viewers share one upstream request");
        feed.published
            .store(true, std::sync::atomic::Ordering::SeqCst);
        assert!(
            results
                .load(2025, 1, false)
                .await
                .unwrap()
                .entries
                .is_empty(),
            "not asked again yet"
        );
        assert_eq!(count(&feed), 1);
        tokio::time::sleep(Duration::from_millis(350)).await;
        assert_eq!(results.load(2025, 1, false).await.unwrap().entries.len(), 1);
        assert_eq!(count(&feed), 2);
        results.load(2025, 1, false).await.unwrap();
        assert_eq!(count(&feed), 2, "a published classification stays cached");
    }

    #[tokio::test]
    async fn pit_stops_ride_along_and_never_fail_the_classification() {
        let feed = feed(None).await;
        feed.published
            .store(true, std::sync::atomic::Ordering::SeqCst);
        let results = client(&feed, Duration::from_secs(30));
        let stopped = results.load(2025, 1, false).await.unwrap();
        assert_eq!(stopped.entries[0].pit_stops, Some(2));
        let no_data = results.load(2025, 3, false).await.unwrap();
        assert_eq!(no_data.entries[0].pit_stops, None, "nothing published yet");
        let broken = results.load(2025, 4, false).await.unwrap();
        assert_eq!(
            broken.entries.len(),
            1,
            "a pit-stop outage keeps the classification"
        );
        assert_eq!(broken.entries[0].pit_stops, None);
    }

    #[tokio::test]
    async fn failures_are_not_retried_immediately_and_serve_saved_results_as_stale() {
        let feed = feed(None).await;
        feed.failing
            .store(true, std::sync::atomic::Ordering::SeqCst);
        let results = client(&feed, Duration::from_millis(300));
        assert!(results.load(2025, 1, false).await.is_err());
        assert!(results.load(2025, 1, false).await.is_err());
        assert_eq!(count(&feed), 1, "an outage is not hammered");
        // Seed a published classification, then let it expire while the feed is down.
        feed.failing
            .store(false, std::sync::atomic::Ordering::SeqCst);
        feed.published
            .store(true, std::sync::atomic::Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(350)).await;
        let fresh = results.load(2025, 1, false).await.unwrap();
        assert!(!fresh.stale);
        let results = Results {
            ttl: Duration::ZERO,
            ..results
        };
        feed.failing
            .store(true, std::sync::atomic::Ordering::SeqCst);
        let stale = results.load(2025, 1, false).await.unwrap();
        assert!(stale.stale);
        assert_eq!(stale.entries.len(), 1);
        assert_eq!(stale.fetched_at, fresh.fetched_at);
        assert_eq!(results.load(2025, 1, true).await.unwrap().mode, "demo");
        assert!(results.load(1900, 1, true).await.is_err());
        assert!(results.load(2025, 0, true).await.is_err());
    }

    #[tokio::test]
    async fn a_slow_race_does_not_block_other_races() {
        let feed = feed(Some(1)).await;
        let results = Arc::new(client(&feed, Duration::from_secs(30)));
        let slow = tokio::spawn({
            let results = results.clone();
            async move { results.load(2025, 1, false).await }
        });
        tokio::time::sleep(Duration::from_millis(100)).await;
        let started = Instant::now();
        results.load(2025, 2, false).await.unwrap();
        assert!(
            started.elapsed() < Duration::from_millis(1000),
            "round 2 waited for round 1"
        );
        slow.await.unwrap().unwrap();
    }
}
