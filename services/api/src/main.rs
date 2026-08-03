//! `cargo run -p api -- [--content <dir>] [--port <port>]`
//! Binds to 127.0.0.1 only — localhost development; deployment fronts this
//! with real infrastructure later.

use std::path::PathBuf;
use std::sync::Arc;

use api::{AppState, load_content, router};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_target(false).init();

    let mut content = PathBuf::from("content");
    let mut port: u16 = 8787;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--content" => content = PathBuf::from(args.next().expect("--content needs a dir")),
            "--port" => port = args.next().expect("--port needs a value").parse()?,
            other => anyhow::bail!("unknown argument {other}"),
        }
    }

    let index = load_content(&content)?;
    tracing::info!(
        "loaded {} packs, {} puzzles, {} outcome sidecars",
        index.packs.len(),
        index.puzzles.len(),
        index.outcomes.len()
    );
    let state = Arc::new(AppState::new(index));

    let addr = std::net::SocketAddr::from(([127, 0, 0, 1], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("listening on http://{addr}");
    axum::serve(listener, router(state)).await?;
    Ok(())
}
