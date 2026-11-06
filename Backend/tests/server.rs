use formula_live_backend::{
    server,
    state::{Snapshot, TimingState},
};
use futures_util::StreamExt;
use std::{sync::Arc, time::Duration};
use tokio::{
    net::TcpListener,
    sync::{watch, RwLock},
    time::timeout,
};

#[tokio::test]
async fn demo_health_websocket_contract_and_shutdown() {
    timeout(Duration::from_secs(10), async {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let state = Arc::new(RwLock::new(TimingState::demo()));
        let (shutdown, receiver) = watch::channel(false);
        let mut server_shutdown = receiver.clone();
        let server = tokio::spawn(async move {
            axum::serve(listener, server::router(state, receiver))
                .with_graceful_shutdown(async move {
                    let _ = server_shutdown.changed().await;
                })
                .await
                .unwrap();
        });
        let http = reqwest::Client::new();
        let health: serde_json::Value = http
            .get(format!("http://{address}/health"))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(
            health,
            serde_json::json!({"mode":"demo","upstream":"simulated"})
        );
        assert_eq!(
            http.get(format!("http://{address}/missing"))
                .send()
                .await
                .unwrap()
                .status(),
            404
        );
        let calendar: serde_json::Value = http
            .get(format!("http://{address}/schedule/2026"))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(calendar["mode"], "demo");
        assert_eq!(calendar["season"], 2026);
        assert!(calendar["fetchedAt"].is_string());
        assert_eq!(calendar["stale"], false);
        assert_eq!(
            calendar["races"][1]["sessions"][1]["name"],
            "Sprint qualifying"
        );
        assert_eq!(
            http.get(format!("http://{address}/schedule/1900"))
                .send()
                .await
                .unwrap()
                .status(),
            400
        );
        let (mut socket, _) = tokio_tungstenite::connect_async(format!("ws://{address}/live"))
            .await
            .unwrap();
        for _ in 0..2 {
            let payload = socket.next().await.unwrap().unwrap().into_text().unwrap();
            let snapshot: Snapshot = serde_json::from_str(&payload).unwrap();
            assert_eq!(snapshot.mode, "demo");
            assert_eq!(snapshot.drivers.len(), 4);
            assert_eq!(snapshot.drivers[0].position, Some(1));
            assert_eq!(snapshot.drivers[0].acronym, "NOR");
            assert!(snapshot.messages[0].message.contains("DEMO"));
            let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
            assert!(value["drivers"][0].get("lapTime").is_some());
            assert!(value.get("updatedAt").is_some());
        }
        shutdown.send(true).unwrap();
        // Open WebSocket connections must not prevent graceful server shutdown.
        let next = socket.next().await;
        assert!(
            next.is_none()
                || matches!(
                    next,
                    Some(Ok(tokio_tungstenite::tungstenite::Message::Close(_)))
                )
        );
        drop(socket);
        server.await.unwrap();
    })
    .await
    .expect("demo integration timed out");
}
