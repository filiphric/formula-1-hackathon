use crate::state::TimingState;
use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use serde_json::{json, Value};
use std::{sync::Arc, time::Duration};
use tokio::sync::{watch, RwLock};

pub type SharedState = Arc<RwLock<TimingState>>;

#[derive(Clone)]
struct AppState {
    timing: SharedState,
    shutdown: watch::Receiver<bool>,
}

pub fn router(timing: SharedState, shutdown: watch::Receiver<bool>) -> Router {
    let state = AppState { timing, shutdown };
    Router::new()
        .route("/health", get(health))
        .route("/live", get(upgrade))
        .with_state(state)
}

async fn health(State(state): State<AppState>) -> Json<Value> {
    let state = state.timing.read().await;
    Json(json!({"mode": state.mode, "upstream": state.upstream}))
}

async fn upgrade(ws: WebSocketUpgrade, State(state): State<AppState>) -> impl IntoResponse {
    ws.max_message_size(1024)
        .max_frame_size(1024)
        .on_upgrade(|socket| stream(socket, state))
}

async fn stream(mut socket: WebSocket, mut state: AppState) {
    // The first interval tick fires immediately, providing the initial snapshot.
    let mut interval = tokio::time::interval(Duration::from_secs(1));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            _ = state.shutdown.changed() => {
                let _ = tokio::time::timeout(Duration::from_secs(1), socket.send(Message::Close(None))).await;
                break;
            }
            _ = interval.tick() => {
                let snapshot = state.timing.read().await.snapshot();
                let Ok(payload) = serde_json::to_string(&snapshot) else { break };
                // Disconnect slow clients rather than growing an unbounded send queue.
                match tokio::time::timeout(Duration::from_secs(5), socket.send(Message::Text(payload.into()))).await {
                    Ok(Ok(())) => {},
                    _ => break,
                }
            }
            message = socket.recv() => {
                match message {
                    None | Some(Err(_)) | Some(Ok(Message::Close(_))) => break,
                    _ => {} // Receiving also services WebSocket ping/pong control frames.
                }
            }
        }
    }
}
