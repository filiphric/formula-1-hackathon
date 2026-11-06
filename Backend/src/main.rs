use anyhow::{bail, Context, Result};
use formula_live_backend::{
    server,
    state::TimingState,
    upstream::{self, Config},
};
use std::{env, path::Path, sync::Arc};
use tokio::{
    net::TcpListener,
    sync::{watch, RwLock},
};
use tracing::info;

#[tokio::main]
async fn main() -> Result<()> {
    // The same .env is found whether launched from the repository root or Backend/.
    let env_file = Path::new(env!("CARGO_MANIFEST_DIR")).join(".env");
    match dotenvy::from_path(env_file) {
        Ok(_) => {}
        Err(dotenvy::Error::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(_) => bail!("Cannot parse Backend/.env; check its dotenv syntax"),
    }
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();
    let args: Vec<_> = env::args().skip(1).collect();
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!("formula-live-backend [--demo]\nReads Backend/.env. HOST defaults to 127.0.0.1; PORT to 8787.");
        return Ok(());
    }
    if args.iter().any(|arg| arg != "--demo") {
        bail!("Unknown argument; use --help");
    }
    let demo = args.iter().any(|arg| arg == "--demo");
    let config = if demo {
        None
    } else {
        Some(Config::from_env()?)
    };
    let host = env::var("HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = env::var("PORT")
        .unwrap_or_else(|_| "8787".into())
        .parse()
        .context("PORT must be a valid port number")?;
    let listener = TcpListener::bind((host.as_str(), port))
        .await
        .context("Cannot bind timing server address")?;
    let state = Arc::new(RwLock::new(if demo {
        TimingState::demo()
    } else {
        TimingState::new("live")
    }));
    let worker = config.map(|config| tokio::spawn(upstream::run(config, state.clone())));
    info!(address = %listener.local_addr()?, mode = if demo { "demo" } else { "live" }, "Formula Live backend ready");
    let (shutdown, shutdown_receiver) = watch::channel(false);
    let result = axum::serve(listener, server::router(state, shutdown_receiver))
        .with_graceful_shutdown(async move {
            shutdown_signal().await;
            let _ = shutdown.send(true);
        })
        .await;
    if let Some(worker) = worker {
        worker.abort();
        let _ = worker.await;
    }
    result.context("Timing server stopped unexpectedly")
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        if let Ok(mut terminate) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            tokio::select! { _ = tokio::signal::ctrl_c() => {}, _ = terminate.recv() => {} }
            return;
        }
    }
    let _ = tokio::signal::ctrl_c().await;
}
