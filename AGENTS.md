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
- When a task is complete, commit and push its changes and open a pull request. Use the `qodo-review-resolver` skill to read the structured PR review, fix supported findings, verify the fixes, and push updates until a completed Qodo review of the current PR head has no open findings. Merge only after that condition and the required checks pass, and after the repository owner explicitly approves that specific PR for merge. Standing workflow instructions and automated reviews do not constitute human sign-off. Honor narrower instructions for individual tasks, including requests to keep work local or not merge. Do not dismiss findings merely to clear the review; request explicit authorization for any dismissal.
