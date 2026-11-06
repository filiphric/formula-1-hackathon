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
