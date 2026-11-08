## Required delivery to the iPhone

After any app change that builds, install it on the user's physical iPhone **Ajfonis**. This is
the user's standing authorization; do not ask again.

- Run `Scripts/install-iphone.sh`. It builds the `FormulaLive` scheme for the device with the
  signing team from `Config.local.xcconfig` (gitignored; template in
  `Config.local.example.xcconfig`), installs over the existing app without uninstalling it,
  and launches it.
- The phone cannot reach `localhost`. Pass `--endpoint ws://<Mac LAN IP>:<port>/live` for a backend
  bound to the LAN (`HOST=0.0.0.0`). Prefer `--demo` for LAN-exposed servers; never expose real
  OpenF1 credentials' data beyond a trusted network, and never commit `.env`.
- A simulator build does not fulfil this. Report the install and launch result separately, and
  state the exact blocker (locked phone, untrusted Mac, signing) if a step fails.
