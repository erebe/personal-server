use crate::sites::Sites;
use anyhow::Context;
use axum::Router;
use axum::http::StatusCode;
use axum::routing::get;
use clap::Parser;
use std::borrow::Cow;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::signal::unix::SignalKind;
use tower::ServiceBuilder;
use tower_http::compression::CompressionLayer;
use tower_http::trace::{DefaultOnResponse, TraceLayer};
use tracing::level_filters::LevelFilter;
use tracing::{Level, info};
use tracing_subscriber::EnvFilter;

mod sites;

#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

async fn health() -> (StatusCode, Cow<'static, str>) {
    (StatusCode::OK, Cow::Borrowed("OK"))
}

/// Static files web server.
///
/// The first label of the requested hostname selects the directory to serve the files from.
/// i.e: https://wstunnel.erebe.eu/index.html serves the file <root-dir>/wstunnel/index.html
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// Bind address where the http server is listening to
    #[arg(long, default_value = "[::]:8080", env = "HTTP_LISTEN")]
    http_listen: String,

    /// Directory containing one sub-directory per hostname to serve
    #[arg(long, default_value = "public", env = "ROOT_DIR")]
    root_dir: PathBuf,
}

fn cli_init<T: clap::Parser>() -> T {
    tracing_subscriber::fmt()
        .with_ansi(true)
        .with_env_filter(
            EnvFilter::builder()
                .with_default_directive(LevelFilter::INFO.into())
                .from_env_lossy(),
        )
        .init();

    T::parse()
}

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let cli: Cli = cli_init();

    let sites =
        Sites::load(&cli.root_dir).with_context(|| format!("Cannot load sites from directory {:?}", cli.root_dir))?;
    if sites.is_empty() {
        info!(
            "No site to serve, {:?} does not contain any sub-directory",
            cli.root_dir
        );
    }
    for (host, dir) in sites.iter() {
        info!("Serving http://{}.* from {:?}", host, dir);
    }

    let listener = TcpListener::bind(&cli.http_listen)
        .await
        .with_context(|| format!("Cannot bind http server on {}", cli.http_listen))?;

    info!("Starting http server on {}", cli.http_listen);
    axum::serve(listener, get_router(sites))
        .with_graceful_shutdown(shutdown_signal())
        .await
        .with_context(|| "Http server failure")?;

    Ok(())
}

fn get_router(sites: Sites) -> Router {
    // TraceLayer logs at debug level by default, so raise the response event to info
    let static_files = Router::new()
        .fallback(sites::serve_static_file)
        .with_state(Arc::new(sites))
        .layer(
            ServiceBuilder::new()
                .layer(
                    TraceLayer::new_for_http()
                        .make_span_with(sites::RequestSpan)
                        .on_response(DefaultOnResponse::new().level(Level::INFO)),
                )
                .layer(CompressionLayer::new()),
        );

    // /health is kept out of the traced router, to not log the probes of kubernetes
    Router::new().route("/health", get(health)).merge(static_files)
}

async fn shutdown_signal() {
    info!("WAITING for program to be killed");
    let mut sigterm = tokio::signal::unix::signal(SignalKind::terminate()).expect("Cannot listen for SIGTERM");

    tokio::select! {
        _ = tokio::signal::ctrl_c() => {},
        _ = sigterm.recv() => {},
    }

    info!("STOPPING received ctrl+c/sigterm signal");
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, header};
    use tower::ServiceExt;

    fn router() -> Router {
        let root_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("public");
        get_router(Sites::load(&root_dir).unwrap())
    }

    async fn get(host: &str, path: &str) -> StatusCode {
        let request = Request::builder()
            .uri(path)
            .header(header::HOST, host)
            .body(Body::empty())
            .unwrap();

        router().oneshot(request).await.unwrap().status()
    }

    #[tokio::test]
    async fn test_serve_existing_site() {
        assert_eq!(get("wstunnel.erebe.eu", "/index.html").await, StatusCode::OK);
        assert_eq!(get("WsTunnel.erebe.eu", "/index.html").await, StatusCode::OK);
        // directory index
        assert_eq!(get("wstunnel.erebe.eu", "/").await, StatusCode::OK);
        // missing file within an existing site
        assert_eq!(get("wstunnel.erebe.eu", "/nope.html").await, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_serve_unknown_site() {
        assert_eq!(get("unknown.erebe.eu", "/index.html").await, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn test_health_is_served_for_any_host() {
        assert_eq!(get("unknown.erebe.eu", "/health").await, StatusCode::OK);
    }
}
