+++
title = "My first post"
date = 2019-11-27
+++

This is my first blog post.

```rust
use lazy_static::lazy_static;
use prometheus::{self, Encoder, IntCounter, TextEncoder};
use std::net::SocketAddr;
use std::sync::Mutex;
use tokio::runtime::{Builder, Runtime};
use tokio::task::JoinHandle;
use warp::reply::WithHeader;
use warp::Filter;

static MAX_THREADS: usize = 2;
lazy_static! {
    static ref TOKIO_RUNTIME: Mutex<Runtime> = Mutex::new({
        Builder::new_multi_thread()
            .thread_name("tokio-warp-http")
            .max_blocking_threads(MAX_THREADS)
            .enable_io()
            .build()
            .unwrap()
    });
    static ref METRICS_PROMETHEUS_NB_CALLS: IntCounter = register_int_counter!(
        "prometheus_endpoint_nb_call",
        "Number of time since startup that the prometheus endpoint got called"
    )
    .unwrap();
}

/// Launch a webserver as a Tokio task
///
/// Use the static tokio runtime to start a webserver.
/// Spawn a thread that block until the webserver stop (never)
pub fn launch(listen_on: &str) -> JoinHandle<()> {
    let listen_on: SocketAddr = listen_on.parse().unwrap_or_else(|_| {
        panic!(
            "Cannot parse webserver listen_on parameter, should be ip:port instead {}",
            listen_on
        )
    });

    info!("Starting tokio runtime");
    TOKIO_RUNTIME.lock().unwrap().spawn(launch_warp(listen_on))
}

/// Start warp webserver
///
/// In most cast, only one should be started per application
async fn launch_warp(listen_on: SocketAddr) {
    let prometheus_srv = warp::path!("metrics").and(warp::get()).map(prometheus_service);

    let healthcheck_srv = warp::path!("healthz").and(warp::get()).map(|| warp::reply::html("OK"));

    let routes = prometheus_srv.or(healthcheck_srv);
    warp::serve(routes).run(listen_on).await;
}

/// Service responsible of the prometheus endpoint
///
/// Warp prometheus metrics endpoint.
///     1. Gather metrics
///     2. Encode them
///     3. return plain/text http response with it
fn prometheus_service() -> WithHeader<Vec<u8>> {
    METRICS_PROMETHEUS_NB_CALLS.inc();

    // Collect metrics and encode to text to send back to the browser
    let mut buffer = Vec::with_capacity(4096);
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    if encoder.encode(&metric_families, &mut buffer).is_err() {
        error!("Cannot encode prometheus metrics");
    }

    warp::reply::with_header(buffer, "Content-Type", prometheus::TEXT_FORMAT)
}

#[cfg(test)]
mod tests {
    use crate::webserver::launch;

    #[test]
    fn test_launch_webserver() {
        let _handle = launch("127.0.0.1:8080");
        let body = reqwest::blocking::get("http://127.0.0.1:8080/metrics")
            .unwrap()
            .text()
            .unwrap();

        assert!(
            body.contains("prometheus_endpoint_nb_call 1"),
            "can't launch properly webserver"
        );
    }
}
```
