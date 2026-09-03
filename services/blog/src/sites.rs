use axum::body::Body;
use axum::extract::State;
use axum::http::{Request, StatusCode, header};
use axum::response::{IntoResponse, Response};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tower::ServiceExt;
use tower_http::services::{ServeDir, ServeFile};
use tower_http::set_status::SetStatus;
use tower_http::trace::MakeSpan;
use tracing::{Level, Span, debug, span};

/// Service serving the static files of a single site, with a `404.html` page as fallback
type StaticFiles = ServeDir<SetStatus<ServeFile>>;

struct Site {
    dir: PathBuf,
    static_files: StaticFiles,
}

/// Sites we serve, indexed by the first label of the hostname they are served on.
/// i.e: the site `wstunnel` serves the files of `<root_dir>/wstunnel` for the hostname `wstunnel.erebe.eu`
pub struct Sites {
    sites: HashMap<String, Site>,
}

impl Sites {
    /// One site per sub-directory of `root_dir`, the name of the directory being the name of the site.
    pub fn load(root_dir: &Path) -> Result<Self, std::io::Error> {
        let mut sites = HashMap::new();
        for entry in std::fs::read_dir(root_dir)? {
            let dir = entry?.path();
            // is_dir follows symlinks, contrary to DirEntry::file_type
            if !dir.is_dir() {
                continue;
            }

            let Some(name) = dir.file_name().and_then(|name| name.to_str()) else {
                continue;
            };

            let static_files = ServeDir::new(&dir)
                .append_index_html_on_directories(true)
                .not_found_service(ServeFile::new(dir.join("404.html")));

            sites.insert(
                name.to_ascii_lowercase(),
                Site {
                    dir: dir.clone(),
                    static_files,
                },
            );
        }

        Ok(Self { sites })
    }

    pub fn is_empty(&self) -> bool {
        self.sites.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = (&str, &Path)> {
        self.sites
            .iter()
            .map(|(name, site)| (name.as_str(), site.dir.as_path()))
    }

    fn get(&self, name: &str) -> Option<StaticFiles> {
        self.sites.get(name).map(|site| site.static_files.clone())
    }
}

/// Serve the file of the request path, looked up in the directory of the site matching the request hostname.
/// i.e: https://wstunnel.erebe.eu/index.html serves the file <root_dir>/wstunnel/index.html
pub async fn serve_static_file(State(sites): State<Arc<Sites>>, request: Request<Body>) -> Response {
    let Some(hostname) = request_hostname(&request) else {
        return (StatusCode::BAD_REQUEST, "Missing Host header\n").into_response();
    };

    let site_name = site_name_of(hostname);
    let Some(static_files) = sites.get(&site_name) else {
        debug!("No site {:?} to serve request {:?}", site_name, request.uri());
        return (StatusCode::NOT_FOUND, "Unknown host\n").into_response();
    };

    static_files.oneshot(request).await.into_response()
}

/// Hostname of the request, without its port. Taken from the uri (http2/http3) or from the Host header (http1)
fn request_hostname<B>(request: &Request<B>) -> Option<&str> {
    let host = match request.uri().host() {
        Some(host) => host,
        None => request.headers().get(header::HOST)?.to_str().ok()?,
    };

    Some(strip_port(host))
}

fn strip_port(host: &str) -> &str {
    // ipv6 literal, i.e: [::1]:8080
    if let Some(end) = host.strip_prefix('[').and_then(|host| host.find(']')) {
        return &host[1..=end];
    }

    match host.split_once(':') {
        Some((host, _port)) => host,
        None => host,
    }
}

/// First label of the hostname, i.e: wstunnel for wstunnel.erebe.eu
fn site_name_of(hostname: &str) -> String {
    hostname.split('.').next().unwrap_or_default().to_ascii_lowercase()
}

/// Ip of the user doing the request, which is the left-most address of the X-Forwarded-For header.
/// The addresses appended by the proxies it went through follow, i.e: X-Forwarded-For: user, proxy1, proxy2
fn downstream_user_of<B>(request: &Request<B>) -> Option<&str> {
    let forwarded_for = request.headers().get("x-forwarded-for")?.to_str().ok()?;
    let user = forwarded_for.split(',').next()?.trim();

    if user.is_empty() { None } else { Some(user) }
}

/// Span of a request, adding the site and the user doing the request to the default fields
#[derive(Clone, Debug)]
pub struct RequestSpan;

impl<B> MakeSpan<B> for RequestSpan {
    fn make_span(&mut self, request: &Request<B>) -> Span {
        let site = request_hostname(request).map(site_name_of).unwrap_or_default();
        let user = downstream_user_of(request).unwrap_or("-");

        span!(
            Level::INFO,
            "request",
            method = %request.method(),
            uri = %request.uri(),
            version = ?request.version(),
            site = %site,
            user = %user,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strip_port() {
        assert_eq!(strip_port("wstunnel.erebe.eu"), "wstunnel.erebe.eu");
        assert_eq!(strip_port("wstunnel.erebe.eu:8080"), "wstunnel.erebe.eu");
        assert_eq!(strip_port("127.0.0.1:8080"), "127.0.0.1");
        assert_eq!(strip_port("[::1]:8080"), "::1");
        assert_eq!(strip_port("[::1]"), "::1");
    }

    #[test]
    fn test_downstream_user_of() {
        let request = |forwarded_for: Option<&str>| {
            let mut request = Request::builder().uri("/");
            if let Some(forwarded_for) = forwarded_for {
                request = request.header("x-forwarded-for", forwarded_for);
            }
            request.body(()).unwrap()
        };

        assert_eq!(downstream_user_of(&request(Some("2001:861::1"))), Some("2001:861::1"));
        assert_eq!(downstream_user_of(&request(Some("1.2.3.4, 10.0.0.1"))), Some("1.2.3.4"));
        assert_eq!(
            downstream_user_of(&request(Some("  1.2.3.4  , 10.0.0.1"))),
            Some("1.2.3.4")
        );
        assert_eq!(downstream_user_of(&request(Some(""))), None);
        assert_eq!(downstream_user_of(&request(None)), None);
    }

    #[test]
    fn test_site_name_of() {
        assert_eq!(site_name_of("wstunnel.erebe.eu"), "wstunnel");
        assert_eq!(site_name_of("WsTunnel.Erebe.eu"), "wstunnel");
        assert_eq!(site_name_of("blog.dev.erebe.eu"), "blog");
        assert_eq!(site_name_of("erebe.eu"), "erebe");
        assert_eq!(site_name_of("localhost"), "localhost");
        assert_eq!(site_name_of(""), "");
    }
}
