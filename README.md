# Formula Live

A native SwiftUI foundation for **macOS 14+ and iOS 17+**, backed by OpenF1.

Includes a shared timing board, lap times, gaps, tyre compounds, race-control messages,
connection settings, reconnect with backoff, and a stale-data indicator. The Mac app
runs natively (not Catalyst). iPad uses the same adaptive layout.

## Run the demo

Requires Xcode and Rust 1.86 or newer (including Cargo).

```sh
cd Backend
cargo run --locked -- --demo
```

Open `FormulaLive.xcodeproj`, select the **FormulaLive** scheme and **My Mac** or an
iOS Simulator, then Run. The default server is `ws://localhost:8787/live`.
Demo is explicitly labelled and uses four fictional sample timing rows; it does not
contact OpenF1 or replay a real race.

## Connect OpenF1 live access

```sh
cd Backend
cp .env.example .env
```

Edit `.env` locally with your OpenF1 account username and password, stop the demo,
and run `cargo run --locked`. `.env` is ignored by Git. Never put these credentials in the
Swift app or commit them. Your paid account must have live access enabled.

The backend exchanges credentials for an OAuth token, renews it before expiry,
loads a REST snapshot, then subscribes to `drivers`, `position`, `intervals`, `laps`,
`stints`, and `race_control` via MQTT/TLS. It sends one normalized WebSocket snapshot
per second. Reconnection refreshes the REST snapshot to recover missed events.
Older updates and updates from another session are ignored. It checks for a new
latest session every minute. Set `SESSION_KEY` to pin a particular session.

The existing Swift JSON contract and `/health` and `/live` routes are preserved.
Credentials are read from `Backend/.env`; exported environment variables take precedence.
`HOST`, `PORT` and `SESSION_KEY` keep their original meanings. The server handles Ctrl-C
and SIGTERM, closes active streams on shutdown, and disconnects slow clients.
`Cargo.lock` pins dependency versions; Node.js and npm are no longer required.

For a standalone release binary:

```sh
cd Backend
cargo build --release --locked
./target/release/formula-live-backend --demo
```

The `.env` default points to the source `Backend/` directory at build time. For a
binary deployed elsewhere, configure the process through environment variables instead.

If a session has finished, the latest snapshot is historical even though the MQTT
connection is open. The UI distinguishes the server connection, upstream connection,
and age of the latest timing. A quiet feed between sessions is expected.

### Physical iPhone

1. Set `HOST=0.0.0.0` in the backend `.env` and restart it.
2. Connect the Mac and iPhone to the same trusted Wi-Fi network.
3. In the app's **Connection** settings, use `ws://YOUR-MAC-LAN-IP:8787/live`.
4. Select your Apple development team in Xcode before running on the phone; allow
   local network access when prompted.

The development server has no client authentication and defaults to loopback.
Binding to the LAN exposes its timing stream to that network. Before internet
hosting, add HTTPS/WSS, app-client authentication, access controls, and connection
limits. The app already accepts `wss://` addresses. Do not expose port 8787 directly
to the internet.

## Layout

- `App/` — SwiftUI application, view state, WebSocket lifecycle and platform configuration.
- `Core/` — Codable/Sendable timing models, also available as a Swift package.
- `Backend/` — Rust server: Tokio, Axum HTTP/WebSockets, rumqttc MQTT/TLS, and reqwest REST.
- `Tests/` — Swift decoding/formatting tests.
- `Scripts/generate-project.rb` — optional Xcode project regeneration (Ruby `xcodeproj` gem).
  The generated project is checked in; regeneration is not needed to build.

## Verify

```sh
swift test
cargo test --locked --manifest-path Backend/Cargo.toml
cargo clippy --locked --manifest-path Backend/Cargo.toml --all-targets -- -D warnings
cargo fmt --manifest-path Backend/Cargo.toml --all -- --check
xcodebuild -project FormulaLive.xcodeproj -scheme FormulaLive \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FormulaLive.xcodeproj -scheme FormulaLive \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The backend tests cover out-of-order events, session isolation, mixed interval
values, lap corrections and bounded race-control history. Integration tests start
the Rust demo server and validate its health endpoint, WebSocket snapshots and graceful
shutdown. Authentication tests use a local mock upstream to verify credential encoding,
bearer headers, token caching and renewal.

Live authentication and delivery require your subscription credentials and a real
session; demo tests cannot verify those. This initial slice does not yet include
track maps, telemetry charts, session browsing, radio playback, TV-delay controls,
background notifications, app icons, or distribution signing.

OpenF1 is unofficial. See [API docs](https://openf1.org/docs/),
[authentication and streaming](https://openf1.org/auth.html), and
[usage/licensing](https://openf1.org/) before commercial distribution.
