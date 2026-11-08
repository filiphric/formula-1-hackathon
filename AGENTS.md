# Project rules

- Use native SwiftUI for macOS/iOS and Rust for the backend.
- Keep shared Swift models in `Core/`, UI in `App/`, and server code in `Backend/`.
- Keep OpenF1 credentials on the backend; never commit secrets or `.env` files.
- Preserve the Swift–Rust JSON contract when changing either side.
- Clearly distinguish demo data, live connections, and stale timing.
- Keep changes focused; add tests for meaningful behavior changes.
- **Work out the expected answer from the request, never from the code.**
- **Before calling it done, deliberately break the code and show that the test fails.**
- **Never weaken a test to make it pass.**
- For Rust changes, run `cargo test --locked`, `cargo fmt --all -- --check`, and `cargo clippy --locked --all-targets -- -D warnings` from `Backend/`.
- For Swift changes, run relevant tests/builds. Report checks you could not run.
- After app or backend changes, close the running app, rebuild the affected targets, restart the backend when its code changed, and reopen the newly built app. Verify the feature against those running builds before calling the work done; do not leave the user connected to an older process.
- When a task is complete, commit and push its changes and open a pull request. Use the `qodo-review-resolver` skill to read the structured PR review, fix supported findings, verify the fixes, and push updates until a completed Qodo review of the current PR head has no open findings. Merge only after that condition and the required checks pass. Do not dismiss findings merely to clear the review; request explicit authorization for any dismissal.

## Required delivery to the iPhone

**Always run the latest build on the iPhone.** After any app change that builds, install it on the
user's physical iPhone **Ajfonis**, so the phone never runs an older build than the Mac app or the
branch. Install again after any further change to the app, to `Core/`, or to anything the app
depends on, even if you installed earlier in the same task. This is the user's standing
authorization; do not ask again.

- Run `Scripts/install-iphone.sh`. It builds the `FormulaLive` scheme for the device with the
  signing team from `Config.local.xcconfig` (gitignored; template in
  `Config.local.example.xcconfig`), installs over the existing app without uninstalling it,
  and launches it.
- **The iPhone runs live data, not demo.** Point it at a backend started without `--demo`, using the
  OpenF1 credentials in `Backend/.env`, so the phone shows real timing, standings and schedule. Never
  install it against a `--demo` backend; demo is for Simulator and automated tests only. Before
  installing, check `GET /health` on that backend reports `"mode":"live"`, and say so in the report.
- The phone cannot reach `localhost`. Pass `--endpoint ws://<Mac LAN IP>:<port>/live` for a live
  backend bound to the LAN (`HOST=0.0.0.0`, default port 8787). When backend code changed, rebuild
  and restart that live backend first, so the phone talks to the new code. Only expose it on the
  user's trusted network (the user has accepted this for live data), and never commit `.env`.
- A simulator build does not fulfil this. Report the install and launch result separately, and
  state the exact blocker (locked phone, untrusted Mac, signing) if a step fails.
