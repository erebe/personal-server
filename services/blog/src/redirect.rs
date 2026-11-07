use axum::http::{StatusCode, Uri};
use axum::response::{IntoResponse, Redirect, Response};
use std::collections::HashMap;
use std::sync::LazyLock;

/// First label of the hostname whose requests are redirected instead of served from a directory.
/// It shadows a `<root_dir>/fork` site.
pub const SITE_NAME: &str = "fork";

/// Short links, by id. i.e: https://fork.erebe.eu/gh redirects to https://github.com/erebe
pub static REDIRECTS: LazyLock<HashMap<&str, &str>> = LazyLock::new(|| {
    HashMap::from([
        ("github", "https://github.com/erebe"),
        ("gh", "https://github.com/erebe"),
        ("linkedin", "https://www.linkedin.com/in/romain-g%C3%A9rard-88579537/"),
        ("articles", "https://www.qovery.com/authors/romain"),
    ])
});

/// Temporary redirect toward the url of the short link whose id is the request path
pub fn redirect_to_target(uri: &Uri) -> Response {
    let id = uri.path().trim_start_matches('/');
    let Some(target) = REDIRECTS.get(id) else {
        return (StatusCode::NOT_FOUND, "Unknown redirect\n").into_response();
    };

    // Not permanent: browsers cache a 301/308 indefinitely, so re-pointing a link would never reach them
    Redirect::temporary(target).into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_redirects_are_absolute_urls() {
        // a relative target is resolved against fork.erebe.eu, i.e: github.com/erebe -> fork.erebe.eu/github.com/erebe
        for (id, target) in REDIRECTS.iter() {
            let uri = target.parse::<Uri>();
            assert!(
                matches!(uri.as_ref().map(Uri::scheme_str), Ok(Some("http" | "https"))),
                "Target of {id:?} is not an http(s) url: {target:?}"
            );
        }
    }
}
