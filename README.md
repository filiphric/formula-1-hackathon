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

## Race weekend design

The native interface takes the official F1 app as its visual reference: a dark canvas,
heavy sans-serif type and one brand-red accent. The window has a single slim app bar
(logo, name, one feed-status pill) and one session hero (circuit, session, how fresh the
timing is). The leaderboard is a timing tower with separate GAP and LAST LAP columns,
a bold position, a team-colour tag, a three-letter code and a red LEADER marker; narrow
widths drop team, then last lap, before the tower scrolls. The driver tracker draws the
circuit as a track surface with a chequered start/finish mark; selecting a driver labels
that driver's marker and shows their detail. The calendar makes the next race a hero with
a live countdown and keeps every other weekend a compact, collapsible row. Spacing,
radius and type come from `RacingStyle.Space`, `Radius` and `Typography`. Tyres show
standard coloured S/M/H/I/W rings, with `?` for missing or unrecognised compounds and
spoken labels for accessibility. Demo, connection and stale-data labels remain visible;
this is an unofficial companion. `-initialTab Schedule` opens the calendar first.

## Live track view

The **On track** card in Live timing plots numbered, team-colored driver markers on
an approximate circuit outline. Select a driver from the picker or click a marker
to highlight it. Race, practice and qualifying use the same active-session feed.
The backend subscribes to OpenF1 `location` and bootstraps the last ten seconds of
coordinates, falling back to the scheduled session end for historical sessions. Each driver retains its own sample timestamp; markers dim after ten
seconds, and the view identifies disconnected, stale, future and ended sessions.
Drivers without coordinates are listed as unavailable. Fresh coordinates can keep
an extended session live past its scheduled end.

Circuit orientation uses the circuit/year rotation from the public MultiViewer API,
as referenced by OpenF1 and FastF1. The backend sends optional `rotationDegrees`;
the app rotates the outline, cars and start/finish together before fitting the map.
Older servers and metadata outages show “Orientation unverified · Raw telemetry”;
missing metadata retries on the next track refresh. Demo geometry stays fictional.

The outline is a completed, non-out-lap location trace from the current session,
with at most 600 points. Up to three recent laps are tried if a trace is sparse. It appears once a sufficiently complete timed lap is
available and retries every minute while unavailable. Coordinates are approximate,
not lane-level tracking. A new session clears both the outline and old locations.
`track` and driver `location` are optional additions to the existing WebSocket
contract; older snapshots still decode and display a waiting state.

Markers interpolate between received samples over at most one second, using a
frame-driven SwiftUI timeline. They stop at the latest sample without predicting
future positions. Long gaps, stale samples, reconnects and session changes reset
motion; Reduce Motion displays the received position immediately. Marker separation
uses stable car-number order so timing-order changes do not reshuffle overlaps.

Demo mode animates four markers around an explicitly fictional circuit, without
contacting OpenF1. It does not reproduce a real race. Live location delivery needs
a paid OpenF1 connection and an active session.

## Schedule

The **Schedule** tab shows each season from 2023 through next year, with All,
Upcoming and Past filters. Expand a weekend for practice, qualifying, sprint
qualifying, sprint and race start times. All published instants are converted to
the device timezone, including the local calendar date and daylight saving time.
Unpublished times remain **Time TBC**. Past means the scheduled race start has
passed; the calendar does not claim a race has finished or show results.

The Rust backend exposes `GET /schedule/{year}` independently of the existing
timing JSON contract. In normal mode it uses the public
[Jolpica race calendar](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/races.md),
so calendar requests do not send OpenF1 credentials. Seasons are cached in memory
for 15 minutes. If refresh fails, the last fetched calendar is returned with
`stale: true`; without cached data the server returns HTTP 502 and the app offers
retry. The app also retains the visible season if its own refresh cannot reach the
backend, showing a saved-data warning; changing server or season clears that view.
Both tabs use the server confirmed with Connect, and prefixed deployment URLs
(e.g. `/formula/live`) retain their prefix for calendar requests. Failed refreshes have a 30-second retry cooldown, and requests for one
season do not block cached calendars for another. The app displays the source, fetch time and stale warning. Client expiration uses
the backend's remaining cache lifetime (`expiresIn`) and monotonic elapsed time
from the request start. Device/server clock skew does not label fresh calendars
stale, and a warm server cache does not receive a new 15-minute window. Responses
without a remaining lifetime are conservatively shown as stale. Use Refresh to
check again after the cache interval. Restarting the backend clears this cache.

`--demo` returns two explicitly fictional sample weekends per selected season,
including a sprint weekend, without making calendar network requests. A future
season may legitimately have no published races. Calendar times can change;
refresh before planning around a session. Existing live mode still requires the
backend's OpenF1 credentials described below.

## Connect OpenF1 live access

```sh
cd Backend
cp -n .env.example .env
chmod 600 .env
```

Edit `.env` locally with the username and password issued for your paid OpenF1 access.
First verify authentication, REST access and all timing MQTT subscriptions:

```sh
cargo run --locked -- --check-live
```

This exits successfully only after all checks pass; it never prints credentials or
tokens. It works between race sessions and times out if the MQTT broker is unreachable.
Then stop the demo and run `cargo run --locked` to serve live data. `.env` is ignored
by Git. Never put these credentials in the Swift app or commit them. Your paid account must have live access enabled.

The backend exchanges credentials for an OAuth token, renews it before expiry,
loads a REST snapshot, then subscribes to `drivers`, `position`, `intervals`, `laps`,
`stints`, `race_control`, and `location` via MQTT/TLS. It sends one normalized WebSocket snapshot
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

To build, install and launch on a connected, trusted iPhone from the command line:

```sh
cp Config.local.example.xcconfig Config.local.xcconfig   # once; set DEVELOPMENT_TEAM
Scripts/install-iphone.sh --device "My iPhone" --endpoint ws://YOUR-MAC-LAN-IP:8787/live
```

The script finds the device by name (default `Ajfonis`), replaces the installed app in place
and `--endpoint` saves the server address in the app (once, via `-seedServerEndpoint`), so later
launches from the home screen keep it and Connection settings can still change it.

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
telemetry charts, historical timing browsing, radio playback, TV-delay controls,
background notifications, app icons, or distribution signing.

OpenF1 is unofficial. See [API docs](https://openf1.org/docs/),
[authentication and streaming](https://openf1.org/auth.html), and
[usage/licensing](https://openf1.org/) before commercial distribution.
