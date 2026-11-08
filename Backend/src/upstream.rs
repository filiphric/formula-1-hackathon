use crate::{
    server::SharedState,
    state::{Session, TOPICS},
};
use anyhow::{bail, Context, Result};
use rumqttc::{AsyncClient, Event, MqttOptions, Packet, QoS, SubscribeFilter, Transport};
use serde_json::Value;
use std::{env, sync::Arc, time::Duration};
use tokio::{
    sync::{mpsc, Mutex},
    time::{sleep, sleep_until, Instant},
};
use tracing::warn;

pub struct Config {
    username: String,
    password: String,
    session_key: String,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let credential = |name: &str| -> Result<String> {
            env::var(name)
                .ok()
                .filter(|value| !value.trim().is_empty())
                .with_context(|| format!("Set {name} in Backend/.env, or run with --demo"))
        };
        let session_key = env::var("SESSION_KEY").unwrap_or_else(|_| "latest".into());
        if session_key != "latest" && session_key.parse::<u64>().ok().filter(|n| *n > 0).is_none() {
            bail!("SESSION_KEY must be 'latest' or a positive session number");
        }
        Ok(Self {
            username: credential("OPENF1_USERNAME")?,
            password: credential("OPENF1_PASSWORD")?,
            session_key,
        })
    }
}

#[derive(Clone)]
struct Token {
    value: String,
    renew_at: Instant,
}

struct OpenF1 {
    config: Config,
    http: reqwest::Client,
    token: Mutex<Option<Token>>,
    token_url: String,
    api_url: String,
}

impl OpenF1 {
    fn new(config: Config) -> Result<Self> {
        Ok(Self {
            config,
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .connect_timeout(Duration::from_secs(15))
                // Credentials and bearer tokens must never follow an upstream redirect.
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
            token: Mutex::new(None),
            token_url: "https://api.openf1.org/token".into(),
            api_url: "https://api.openf1.org/v1".into(),
        })
    }

    async fn authenticate(&self) -> Result<Token> {
        let mut cached = self.token.lock().await;
        if let Some(token) = cached
            .as_ref()
            .filter(|token| Instant::now() < token.renew_at)
        {
            return Ok(token.clone());
        }
        let response = self
            .http
            .post(&self.token_url)
            .form(&[
                ("username", &self.config.username),
                ("password", &self.config.password),
            ])
            .send()
            .await
            .context("OpenF1 authentication request failed")?;
        if !response.status().is_success() {
            bail!("OpenF1 authentication returned HTTP {}", response.status());
        }
        let data: Value = response
            .json()
            .await
            .context("Invalid OpenF1 token response")?;
        let value = data["access_token"]
            .as_str()
            .filter(|s| !s.is_empty())
            .context("OpenF1 returned no access token")?
            .to_string();
        let seconds = data["expires_in"]
            .as_u64()
            .or_else(|| data["expires_in"].as_str().and_then(|s| s.parse().ok()))
            .unwrap_or(3600)
            .clamp(1, 86400);
        let margin = (seconds / 10).clamp(1, 120);
        let token = Token {
            value,
            renew_at: Instant::now() + Duration::from_secs(seconds.saturating_sub(margin).max(1)),
        };
        *cached = Some(token.clone());
        Ok(token)
    }

    async fn session(&self) -> Result<Session> {
        let sessions = self.get("sessions", &self.config.session_key).await?;
        serde_json::from_value(
            sessions
                .last()
                .cloned()
                .context("No OpenF1 session found")?,
        )
        .map_err(Into::into)
    }

    async fn get(&self, endpoint: &str, session_key: &str) -> Result<Vec<Value>> {
        self.filtered(endpoint, session_key, &[]).await
    }

    async fn filtered(
        &self,
        endpoint: &str,
        session_key: &str,
        filters: &[(&str, String)],
    ) -> Result<Vec<Value>> {
        let token = self.authenticate().await?;
        let response = self
            .http
            .get(format!("{}/{endpoint}", self.api_url))
            .query(&[("session_key", session_key)])
            .query(filters)
            .bearer_auth(&token.value)
            .send()
            .await
            .context("OpenF1 snapshot request failed")?;
        // OpenF1 returns 404 for empty datasets, including intervals outside races.
        if endpoint != "sessions" && response.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(Vec::new());
        }
        if response.status() == reqwest::StatusCode::UNAUTHORIZED {
            let mut cached = self.token.lock().await;
            if cached.as_ref().is_some_and(|t| t.value == token.value) {
                *cached = None;
            }
        }
        if !response.status().is_success() {
            bail!("OpenF1 {endpoint} returned HTTP {}", response.status());
        }
        response
            .json()
            .await
            .context("Invalid OpenF1 snapshot response")
    }
}

/// Verify paid access without exposing credentials or requiring live timing events.
pub async fn check_live(config: Config) -> Result<()> {
    let api = OpenF1::new(config)?;
    check_live_with_api(&api).await
}

async fn check_live_with_api(api: &OpenF1) -> Result<()> {
    let token = api.authenticate().await?;
    api.session().await?;
    let options = mqtt_options(&api.config.username, &token.value);
    tokio::time::timeout(Duration::from_secs(30), verify_mqtt(options))
        .await
        .context("OpenF1 MQTT check timed out after 30 seconds")??;
    Ok(())
}

fn mqtt_options(username: &str, token: &str) -> MqttOptions {
    let client_id = format!(
        "formula-live-{}-{}",
        std::process::id(),
        chrono::Utc::now().timestamp_millis()
    );
    let mut options = MqttOptions::new(client_id, "mqtt.openf1.org", 8883);
    options.set_transport(Transport::tls_with_default_config());
    options.set_credentials(username, token);
    options.set_keep_alive(Duration::from_secs(30));
    options
}

fn timing_subscriptions() -> [SubscribeFilter; 8] {
    TOPICS.map(|topic| SubscribeFilter::new(format!("v1/{topic}"), QoS::AtMostOnce))
}

fn verify_subscription(ack: &rumqttc::SubAck) -> Result<bool> {
    if ack.return_codes.len() != TOPICS.len()
        || ack
            .return_codes
            .iter()
            .take(TOPICS.len() - 1)
            .any(|code| matches!(code, rumqttc::SubscribeReasonCode::Failure))
    {
        bail!("OpenF1 MQTT subscription was rejected or incomplete");
    }
    Ok(!matches!(
        ack.return_codes.last(),
        Some(rumqttc::SubscribeReasonCode::Failure)
    ))
}

async fn verify_mqtt(options: MqttOptions) -> Result<()> {
    let (client, mut events) = AsyncClient::new(options, 16);
    loop {
        match events
            .poll()
            .await
            .context("OpenF1 MQTT access check failed")?
        {
            Event::Incoming(Packet::ConnAck(_)) => {
                client.subscribe_many(timing_subscriptions()).await?;
            }
            Event::Incoming(Packet::SubAck(ack)) => {
                if !verify_subscription(&ack)? {
                    bail!("OpenF1 MQTT location subscription was rejected");
                }
                return Ok(());
            }
            _ => {}
        }
    }
}

pub async fn run(config: Config, state: SharedState) {
    let api = match OpenF1::new(config) {
        Ok(api) => Arc::new(api),
        Err(_) => {
            state.write().await.upstream = "HTTP client unavailable".into();
            return;
        }
    };
    let (resync, receiver) = mpsc::channel(1);
    // Both futures belong to this task, so shutdown also cancels in-flight requests.
    tokio::join!(
        mqtt_loop(api.clone(), state.clone(), resync),
        snapshot_loop(api, state, receiver)
    );
}

async fn snapshot_loop(api: Arc<OpenF1>, state: SharedState, mut resync: mpsc::Receiver<()>) {
    let mut timer = tokio::time::interval(Duration::from_secs(60));
    timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut loaded_session = None;
    loop {
        let force = tokio::select! {
            _ = timer.tick() => false,
            signal = resync.recv() => { if signal.is_none() { return; } true },
        };
        match load_snapshot(&api, &state, loaded_session, force).await {
            Ok(key) => loaded_session = Some(key),
            Err(error) => {
                loaded_session = None; // Retry a partial bootstrap at the next tick.
                state.write().await.upstream = "snapshot unavailable".into();
                warn!(%error, "Could not refresh OpenF1 snapshot; retaining last known data");
            }
        }
    }
}

async fn load_snapshot(
    api: &OpenF1,
    state: &SharedState,
    loaded: Option<i64>,
    force: bool,
) -> Result<i64> {
    let session = api.session().await?;
    let key = session.session_key;
    if !force && loaded == Some(key) {
        refresh_track(api, state, key).await;
        return Ok(key);
    }
    let session_end = session.date_end.clone();
    state.write().await.set_session(session);
    for topic in TOPICS.into_iter().filter(|topic| *topic != "location") {
        // Avoid bursts beyond the supporter REST request rate.
        sleep(Duration::from_millis(350)).await;
        let records = api.get(topic, &key.to_string()).await?;
        let mut state = state.write().await;
        for record in records {
            state.apply(topic, record);
        }
    }
    // Try current activity first: red flags can extend a session beyond its schedule.
    let now = chrono::Utc::now();
    let mut ends = vec![now];
    if let Ok(end) = chrono::DateTime::parse_from_rfc3339(&session_end) {
        let end = end.with_timezone(&chrono::Utc);
        if end < now - chrono::Duration::seconds(10) {
            ends.push(end);
        }
    }
    for end in ends {
        sleep(Duration::from_millis(350)).await;
        let filters = [
            ("date>", (end - chrono::Duration::seconds(10)).to_rfc3339()),
            ("date<", (end + chrono::Duration::seconds(1)).to_rfc3339()),
        ];
        match api.filtered("location", &key.to_string(), &filters).await {
            Ok(records) if !records.is_empty() => {
                let mut state = state.write().await;
                for record in records {
                    state.apply("location", record);
                }
                break;
            }
            Ok(_) => {}
            Err(error) => warn!(%error, "Location bootstrap unavailable; waiting for stream"),
        }
    }
    refresh_track(api, state, key).await;
    Ok(key)
}

async fn refresh_track(api: &OpenF1, state: &SharedState, key: i64) {
    if state.read().await.track.is_some() {
        return;
    }
    let result: Result<()> = async {
        sleep(Duration::from_millis(350)).await;
        let laps = api.get("laps", &key.to_string()).await?;
        let mut candidates: Vec<_> = laps
            .iter()
            .filter_map(|lap| {
                let duration = lap["lap_duration"].as_f64()?;
                let start =
                    chrono::DateTime::parse_from_rfc3339(lap["date_start"].as_str()?).ok()?;
                (duration.is_finite()
                    && (20.0..=300.0).contains(&duration)
                    && lap["is_pit_out_lap"].as_bool() == Some(false)
                    && lap["driver_number"].as_i64().is_some())
                .then_some((lap, start, duration))
            })
            .collect();
        candidates.sort_by_key(|(_, start, _)| std::cmp::Reverse(*start));
        // Bound retries while allowing a sparse newest lap to fall back to another trace.
        for (lap, start, duration) in candidates.into_iter().take(3) {
            sleep(Duration::from_millis(350)).await;
            let end = start + chrono::Duration::milliseconds((duration * 1000.0) as i64);
            let records = api
                .filtered(
                    "location",
                    &key.to_string(),
                    &[
                        ("driver_number", lap["driver_number"].to_string()),
                        ("date>", start.to_rfc3339()),
                        ("date<", end.to_rfc3339()),
                    ],
                )
                .await?;
            if let Some(track) = reference_layout(records, key, start, end) {
                let mut state = state.write().await;
                if state.session.as_ref().map(|s| s.session_key) == Some(key) {
                    state.track = Some(track);
                }
                break;
            }
        }
        Ok(())
    }
    .await;
    if let Err(error) = result {
        warn!(%error, "Track outline unavailable; will retry");
    }
}

fn reference_layout(
    records: Vec<Value>,
    key: i64,
    start: chrono::DateTime<chrono::FixedOffset>,
    end: chrono::DateTime<chrono::FixedOffset>,
) -> Option<crate::state::TrackLayout> {
    let mut locations: Vec<_> = records
        .iter()
        .filter(|r| r["session_key"].as_i64() == Some(key))
        .filter_map(|r| {
            let x = r["x"].as_f64()?;
            let y = r["y"].as_f64()?;
            let date = chrono::DateTime::parse_from_rfc3339(r["date"].as_str()?).ok()?;
            (x.is_finite()
                && y.is_finite()
                && (x != 0.0 || y != 0.0)
                && date >= start
                && date <= end)
                .then_some((date, crate::state::TrackPoint { x, y }))
        })
        .collect();
    locations.sort_by_key(|(date, _)| *date);
    if locations.len() < 20
        || locations.first()?.0 - start > chrono::Duration::seconds(2)
        || end - locations.last()?.0 > chrono::Duration::seconds(2)
        || locations
            .windows(2)
            .any(|w| w[1].0 - w[0].0 > chrono::Duration::seconds(3))
    {
        return None;
    }
    let stride = locations.len().div_ceil(600);
    Some(crate::state::TrackLayout {
        source: "OpenF1 · Approximate completed-lap trace".into(),
        points: locations
            .into_iter()
            .step_by(stride)
            .map(|(_, p)| p)
            .collect(),
    })
}

async fn mqtt_loop(api: Arc<OpenF1>, state: SharedState, resync: mpsc::Sender<()>) {
    let mut retry = 2;
    loop {
        match mqtt_connection(&api, &state, &resync, &mut retry).await {
            Ok(()) => {} // The token renewal deadline starts a fresh authenticated connection.
            Err(error) => {
                state.write().await.upstream = "reconnecting".into();
                warn!(%error, retry_seconds = retry, "OpenF1 live connection unavailable");
                sleep(Duration::from_secs(retry)).await;
                retry = (retry * 2).min(30);
            }
        }
    }
}

async fn mqtt_connection(
    api: &OpenF1,
    state: &SharedState,
    resync: &mpsc::Sender<()>,
    retry: &mut u64,
) -> Result<()> {
    let token = api.authenticate().await?;
    let options = mqtt_options(&api.config.username, &token.value);
    let (client, mut events) = AsyncClient::new(options, 16);
    loop {
        tokio::select! {
            _ = sleep_until(token.renew_at) => {
                state.write().await.upstream = "renewing token".into();
                return Ok(()); // Drop the old broker connection, then obtain a fresh token.
            },
            event = events.poll() => match event.context("MQTT connection failed")? {
                Event::Incoming(Packet::ConnAck(_)) => {
                    *retry = 2;
                    state.write().await.upstream = "subscribing".into();
                    client.subscribe_many(timing_subscriptions()).await?;
                },
                Event::Incoming(Packet::SubAck(ack)) => {
                    if !verify_subscription(&ack)? { warn!("OpenF1 location subscription rejected; continuing timing without location stream"); }
                    state.write().await.upstream = "connected".into();
                    let _ = resync.try_send(());
                },
                Event::Incoming(Packet::Publish(message)) => {
                    let Some(topic) = message.topic.strip_prefix("v1/") else { continue };
                    match serde_json::from_slice::<Value>(&message.payload) {
                        Ok(Value::Array(records)) => {
                            let mut state = state.write().await;
                            for record in records { state.apply(topic, record); }
                        },
                        Ok(record @ Value::Object(_)) => state.write().await.apply(topic, record),
                        _ => warn!("Ignored malformed OpenF1 message"),
                    }
                },
                _ => {},
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        extract::{Form, State},
        http::HeaderMap,
        routing::{get, post},
        Json, Router,
    };
    use serde_json::json;
    use std::{
        collections::HashMap,
        sync::atomic::{AtomicUsize, Ordering},
    };
    use tokio::net::TcpListener;

    async fn session_api(
        response: Value,
        session_key: &str,
    ) -> (OpenF1, tokio::task::JoinHandle<()>) {
        use axum::extract::Query;

        async fn sessions(
            Query(query): Query<HashMap<String, String>>,
            State((response, expected_key)): State<(Value, String)>,
        ) -> Json<Value> {
            assert_eq!(query["session_key"], expected_key);
            Json(response)
        }
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let app = Router::new()
            .route("/sessions", get(sessions))
            .with_state((response, session_key.to_string()));
        let server = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        let mut api = OpenF1::new(Config {
            username: "test-user".into(),
            password: "test-password".into(),
            session_key: session_key.into(),
        })
        .unwrap();
        api.api_url = format!("http://{address}");
        // Keep authentication local; these tests exercise session validation.
        *api.token.lock().await = Some(Token {
            value: "test-token".into(),
            renew_at: Instant::now() + Duration::from_secs(60),
        });
        (api, server)
    }

    #[tokio::test]
    async fn live_check_rejects_missing_or_malformed_sessions_before_mqtt() {
        for (response, expected_error) in [
            (json!([]), "No OpenF1 session found"),
            (
                json!([{"session_key": 999999999}]),
                "missing field `session_name`",
            ),
        ] {
            let (api, server) = session_api(response, "999999999").await;
            let result =
                tokio::time::timeout(Duration::from_secs(2), check_live_with_api(&api)).await;
            server.abort();
            let error = result
                .expect("session failure must precede MQTT verification")
                .unwrap_err();
            assert_eq!(error.to_string(), expected_error);
        }
    }

    #[tokio::test]
    async fn session_lookup_accepts_a_usable_session() {
        let response = json!([{
            "session_key": 9158,
            "session_name": "Race",
            "circuit_short_name": "Monza",
            "date_start": "2023-09-03T13:00:00+00:00",
            "date_end": "2023-09-03T15:00:00+00:00"
        }]);
        let (api, server) = session_api(response, "latest").await;
        let session = api.session().await.unwrap();
        server.abort();
        assert_eq!(session.session_key, 9158);
        assert_eq!(session.session_name, "Race");
    }

    #[tokio::test]
    async fn practice_bootstrap_survives_empty_intervals_and_bounds_location_queries() {
        use axum::extract::{Path, Query};
        async fn endpoint(
            Path(endpoint): Path<String>,
            Query(query): Query<HashMap<String, String>>,
        ) -> axum::response::Response {
            use axum::response::IntoResponse;
            let start = chrono::DateTime::parse_from_rfc3339("2026-11-06T12:00:00Z").unwrap();
            let data = match endpoint.as_str() {
                "sessions" => {
                    json!([{"session_key":42,"session_name":"Practice 1","circuit_short_name":"Test",
                    "date_start":start.to_rfc3339(),"date_end":"2026-11-06T12:02:00Z"}])
                }
                "drivers" => json!([{"session_key":42,"driver_number":4,"full_name":"Norris"}]),
                "intervals" => return axum::http::StatusCode::NOT_FOUND.into_response(),
                "laps" => {
                    json!([{"session_key":42,"driver_number":4,"date_start":start.to_rfc3339(),"lap_duration":90,"is_pit_out_lap":false},
                    {"session_key":42,"driver_number":4,"date_start":(start+chrono::Duration::seconds(10)).to_rfc3339(),"lap_duration":90,"is_pit_out_lap":false}])
                }
                "location" => {
                    assert_eq!(query["session_key"], "42");
                    let from = chrono::DateTime::parse_from_rfc3339(&query["date>"]).unwrap();
                    let to = chrono::DateTime::parse_from_rfc3339(&query["date<"]).unwrap();
                    if query.contains_key("driver_number") {
                        assert_eq!(query["driver_number"], "4");
                        assert_eq!((to - from).num_seconds(), 90);
                        if from != start {
                            return Json(json!([])).into_response();
                        }
                        json!((0..=900).map(|i| json!({"session_key":42,"driver_number":4,
                            "date":(start+chrono::Duration::milliseconds(i*100)).to_rfc3339(),"x":100+i,"y":200+i})).collect::<Vec<_>>())
                    } else {
                        assert_eq!((to - from).num_seconds(), 11);
                        assert!(to > chrono::Utc::now() - chrono::Duration::seconds(5));
                        json!([{"session_key":42,"driver_number":4,"date":"2026-11-06T12:01:59Z","x":800,"y":900}])
                    }
                }
                _ => json!([]),
            };
            Json(data).into_response()
        }
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            axum::serve(listener, Router::new().route("/{endpoint}", get(endpoint)))
                .await
                .unwrap();
        });
        let mut api = OpenF1::new(Config {
            username: "test".into(),
            password: "test".into(),
            session_key: "42".into(),
        })
        .unwrap();
        api.api_url = format!("http://{address}");
        *api.token.lock().await = Some(Token {
            value: "test".into(),
            renew_at: Instant::now() + Duration::from_secs(60),
        });
        let state = Arc::new(tokio::sync::RwLock::new(crate::state::TimingState::new(
            "live",
        )));
        assert_eq!(load_snapshot(&api, &state, None, false).await.unwrap(), 42);
        let snapshot = state.read().await.snapshot();
        assert_eq!(snapshot.session.unwrap().name, "Practice 1");
        assert_eq!(snapshot.drivers[0].location.as_ref().unwrap().x, 800.0);
        assert!(snapshot.track.unwrap().points.len() >= 20);
        server.abort();
    }

    #[test]
    fn optional_location_refusal_keeps_timing_subscriptions_usable() {
        use rumqttc::{SubAck, SubscribeReasonCode};
        let mut ack = SubAck::new(1, vec![SubscribeReasonCode::Success(QoS::AtMostOnce); 8]);
        assert!(verify_subscription(&ack).unwrap());
        ack.return_codes[7] = SubscribeReasonCode::Failure;
        assert!(!verify_subscription(&ack).unwrap());
        // Location is the only optional topic; a refused radio topic is a hard failure.
        ack.return_codes[7] = SubscribeReasonCode::Success(QoS::AtMostOnce);
        ack.return_codes[6] = SubscribeReasonCode::Failure;
        assert!(verify_subscription(&ack).is_err());
        ack.return_codes[6] = SubscribeReasonCode::Success(QoS::AtMostOnce);
        ack.return_codes[2] = SubscribeReasonCode::Failure;
        assert!(verify_subscription(&ack).is_err());
        ack.return_codes.truncate(5);
        assert!(verify_subscription(&ack).is_err());
    }

    #[test]
    fn layout_requires_a_complete_trace_in_time_order_and_bounds_its_size() {
        let start = chrono::DateTime::parse_from_rfc3339("2026-11-06T12:00:00Z").unwrap();
        let end = start + chrono::Duration::seconds(90);
        let records: Vec<_> = (0..=900)
            .rev()
            .map(|i| {
                json!({
                    "session_key":42,"driver_number":4,"x":i+100,"y":i+200,
                    "date":(start+chrono::Duration::milliseconds(i*100)).to_rfc3339()
                })
            })
            .collect();
        let layout = reference_layout(records.clone(), 42, start, end).unwrap();
        assert!(layout.points.len() <= 600);
        assert_eq!(layout.points[0].x, 100.0);
        assert!(layout.points.last().unwrap().x > 990.0);
        assert!(reference_layout(records.clone(), 43, start, end).is_none());
        let missing_start = records.iter().take(400).cloned().collect();
        assert!(reference_layout(missing_start, 42, start, end).is_none());
        let missing_fractional_start = records
            .iter()
            .filter(|r| r["x"].as_i64().unwrap() >= 129)
            .cloned()
            .collect();
        assert!(reference_layout(missing_fractional_start, 42, start, end).is_none());
        let fractional_gap = records
            .iter()
            .filter(|r| !(500..538).contains(&r["x"].as_i64().unwrap()))
            .cloned()
            .collect();
        assert!(reference_layout(fractional_gap, 42, start, end).is_none());
        let gap = records
            .into_iter()
            .filter(|r| r["x"].as_i64().unwrap() < 300 || r["x"].as_i64().unwrap() > 500)
            .collect();
        assert!(reference_layout(gap, 42, start, end).is_none());
    }

    #[test]
    fn mqtt_uses_access_token_with_tls_and_documented_broker() {
        let options = mqtt_options("paid@example.com", "oauth-token");
        assert_eq!(options.broker_address(), ("mqtt.openf1.org".into(), 8883));
        assert_eq!(
            options.credentials(),
            Some(("paid@example.com".into(), "oauth-token".into()))
        );
        assert!(matches!(options.transport(), Transport::Tls(_)));
    }

    #[tokio::test]
    async fn mqtt_check_requires_every_timing_subscription() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        use tokio::net::TcpStream;

        async fn packet(socket: &mut TcpStream) -> (u8, Vec<u8>) {
            let header = socket.read_u8().await.unwrap();
            let mut length = 0usize;
            let mut multiplier = 1;
            loop {
                let byte = socket.read_u8().await.unwrap();
                length += usize::from(byte & 127) * multiplier;
                if byte & 128 == 0 {
                    break;
                }
                multiplier *= 128;
                assert!(multiplier <= 128 * 128 * 128);
            }
            assert!(length <= 4096);
            let mut bytes = vec![0; length];
            socket.read_exact(&mut bytes).await.unwrap();
            (header, bytes)
        }

        // Eight grants succeed; a refusal or an incomplete acknowledgement must fail.
        for (grants, expected_success) in [
            (vec![0; 8], true),
            (vec![0, 0, 0, 0, 0, 0, 0, 128], false),
            (vec![0; 7], false),
        ] {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let port = listener.local_addr().unwrap().port();
            let broker = tokio::spawn(async move {
                let (mut socket, _) = listener.accept().await.unwrap();
                assert_eq!(packet(&mut socket).await.0, 0x10);
                socket.write_all(&[0x20, 2, 0, 0]).await.unwrap();
                let (kind, subscribe) = packet(&mut socket).await;
                assert_eq!(kind, 0x82);
                let mut filters = Vec::new();
                let mut cursor = 2;
                while cursor < subscribe.len() {
                    let length =
                        u16::from_be_bytes([subscribe[cursor], subscribe[cursor + 1]]) as usize;
                    cursor += 2;
                    filters.push(
                        String::from_utf8(subscribe[cursor..cursor + length].to_vec()).unwrap(),
                    );
                    cursor += length;
                    assert_eq!(subscribe[cursor], 0); // QoS 0
                    cursor += 1;
                }
                assert_eq!(
                    filters,
                    [
                        "v1/drivers",
                        "v1/position",
                        "v1/intervals",
                        "v1/laps",
                        "v1/stints",
                        "v1/race_control",
                        "v1/team_radio",
                        "v1/location"
                    ]
                );
                let mut ack = vec![0x90, (2 + grants.len()) as u8, subscribe[0], subscribe[1]];
                ack.extend(grants);
                socket.write_all(&ack).await.unwrap();
            });
            let options = MqttOptions::new("test-check", "127.0.0.1", port);
            let result = tokio::time::timeout(Duration::from_secs(3), verify_mqtt(options))
                .await
                .unwrap();
            broker.await.unwrap();
            assert_eq!(result.is_ok(), expected_success);
        }
    }

    #[tokio::test]
    async fn authentication_encodes_credentials_caches_tokens_and_renews() {
        let calls = Arc::new(AtomicUsize::new(0));
        async fn token(
            State(calls): State<Arc<AtomicUsize>>,
            Form(form): Form<HashMap<String, String>>,
        ) -> Json<Value> {
            assert_eq!(form["username"], "test+user@example.com");
            assert_eq!(form["password"], "test&= password");
            calls.fetch_add(1, Ordering::SeqCst);
            Json(json!({"access_token":"test-token","expires_in":"3600"}))
        }
        async fn sessions(headers: HeaderMap) -> Json<Value> {
            assert_eq!(headers["authorization"], "Bearer test-token");
            Json(json!([]))
        }
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let app = Router::new()
            .route("/token", post(token))
            .route("/sessions", get(sessions))
            .with_state(calls.clone());
        let server = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        let mut api = OpenF1::new(Config {
            username: "test+user@example.com".into(),
            password: "test&= password".into(),
            session_key: "latest".into(),
        })
        .unwrap();
        api.token_url = format!("http://{address}/token");
        api.api_url = format!("http://{address}");
        api.authenticate().await.unwrap();
        api.get("sessions", "latest").await.unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        api.token.lock().await.as_mut().unwrap().renew_at = Instant::now();
        api.authenticate().await.unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        server.abort();
    }
}
