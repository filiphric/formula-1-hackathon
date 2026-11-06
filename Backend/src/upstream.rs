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
        let token = self.authenticate().await?;
        let response = self
            .http
            .get(format!("{}/{endpoint}", self.api_url))
            .query(&[("session_key", session_key)])
            .bearer_auth(&token.value)
            .send()
            .await
            .context("OpenF1 snapshot request failed")?;
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

fn timing_subscriptions() -> [SubscribeFilter; 6] {
    TOPICS.map(|topic| SubscribeFilter::new(format!("v1/{topic}"), QoS::AtMostOnce))
}

fn verify_subscription(ack: &rumqttc::SubAck) -> Result<()> {
    if ack.return_codes.len() != TOPICS.len()
        || ack
            .return_codes
            .iter()
            .any(|code| matches!(code, rumqttc::SubscribeReasonCode::Failure))
    {
        bail!("OpenF1 MQTT subscription was rejected or incomplete");
    }
    Ok(())
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
                verify_subscription(&ack)?;
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
        return Ok(key);
    }
    state.write().await.set_session(session);
    for topic in TOPICS {
        // Avoid bursts beyond the supporter REST request rate.
        sleep(Duration::from_millis(350)).await;
        let records = api.get(topic, &key.to_string()).await?;
        let mut state = state.write().await;
        for record in records {
            state.apply(topic, record);
        }
    }
    Ok(key)
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
                    verify_subscription(&ack)?;
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

        // Six grants succeed; a refusal or an incomplete acknowledgement must fail.
        for (grants, expected_success) in [
            (vec![0; 6], true),
            (vec![0, 0, 0, 0, 0, 128], false),
            (vec![0; 5], false),
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
                        "v1/race_control"
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
