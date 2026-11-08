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

## Pull request review and merge

- When a task is complete, commit, push and open a pull request.
- Read the structured Qodo review with the `qodo-review-resolver` skill. **Fix only High and Critical
  findings.** Medium, Low and informational findings are not required to be fixed and do not block the merge.
- **Merge automatically** once the required checks pass and no High or Critical finding is open. Do not wait
  for a Qodo review of the latest head when none of its findings is High or Critical.
- Never dismiss a finding merely to clear the review; dismissal still needs the user's explicit go.
