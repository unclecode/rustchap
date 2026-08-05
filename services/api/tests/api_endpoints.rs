//! Router-level tests against the real repo content, including one genuine
//! live compilation through the HTTP path.

use std::path::Path;
use std::sync::Arc;

use api::{AppState, ContentIndex, load_content, router};
use http_body_util::BodyExt;
use tower::ServiceExt;

fn content_root() -> &'static Path {
    Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../../content"))
}

async fn get_json(app: axum::Router, uri: &str) -> (u16, serde_json::Value) {
    let response = app
        .oneshot(
            axum::http::Request::builder()
                .uri(uri)
                .body(axum::body::Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status().as_u16();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

async fn post_json(
    app: axum::Router,
    uri: &str,
    body: serde_json::Value,
) -> (u16, serde_json::Value) {
    let response = app
        .oneshot(
            axum::http::Request::builder()
                .method("POST")
                .uri(uri)
                .header("content-type", "application/json")
                .body(axum::body::Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status().as_u16();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

fn optimal_submission() -> serde_json::Value {
    serde_json::json!({
        "puzzle_id": "move-or-borrow.001",
        "puzzle_version": 1,
        "operations": [
            { "op": "select", "slot_id": "arg", "choice_id": "c2" },
            { "op": "select", "slot_id": "param_ty", "choice_id": "t3" }
        ]
    })
}

#[tokio::test]
async fn serves_packs_and_puzzles() {
    let state = Arc::new(AppState::new(load_content(content_root()).unwrap()));

    let (status, packs) = get_json(router(state.clone()), "/v1/packs").await;
    assert_eq!(status, 200);
    let packs = packs.as_array().unwrap();
    assert!(
        packs.len() >= 12,
        "full curriculum: content decks + planned empty decks"
    );
    let index: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(content_root().join("packs/index.json")).unwrap(),
    )
    .unwrap();
    let expected: Vec<&str> = index["order"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap())
        .collect();
    let served: Vec<&str> = packs.iter().map(|p| p["id"].as_str().unwrap()).collect();
    assert_eq!(
        served, expected,
        "packs follow the curriculum order from packs/index.json, not directory order"
    );
    assert!(
        packs
            .iter()
            .all(|p| p["order"].as_array().is_some_and(|o| !o.is_empty())),
        "every deck in the curriculum has content (15/15 alive since content batch 5)"
    );

    let (status, puzzle) = get_json(router(state.clone()), "/v1/puzzles/move-or-borrow.001").await;
    assert_eq!(status, 200);
    assert_eq!(puzzle["title"], "Use It Twice");

    let (status, detail) = get_json(router(state.clone()), "/v1/packs/build-the-iterator").await;
    assert_eq!(status, 200);
    assert!(
        !detail["puzzles"].as_array().unwrap().is_empty(),
        "pack detail inlines its puzzles"
    );

    let (status, _) = get_json(router(state), "/v1/puzzles/nope.001").await;
    assert_eq!(status, 404);
}

#[tokio::test]
async fn evaluate_hits_precomputed_outcomes() {
    let state = Arc::new(AppState::new(load_content(content_root()).unwrap()));
    let (status, body) = post_json(
        router(state),
        "/v1/puzzles/move-or-borrow.001/evaluate",
        optimal_submission(),
    )
    .await;
    assert_eq!(status, 200);
    assert_eq!(
        body["cached"], true,
        "precomputed outcomes answer without compiling"
    );
    assert_eq!(body["result"]["status"], "solved");
    assert_eq!(body["result"]["rank"], "optimal");
}

#[tokio::test]
async fn evaluate_version_mismatch_is_conflict() {
    let state = Arc::new(AppState::new(load_content(content_root()).unwrap()));
    let mut submission = optimal_submission();
    submission["puzzle_version"] = serde_json::json!(99);
    let (status, _) = post_json(
        router(state),
        "/v1/puzzles/move-or-borrow.001/evaluate",
        submission,
    )
    .await;
    assert_eq!(status, 409);
}

#[tokio::test]
async fn evaluate_compiles_live_on_cache_miss_then_caches() {
    // Strip the sidecars so the request must reach the real compiler.
    let index = load_content(content_root()).unwrap();
    let state = Arc::new(AppState::new(ContentIndex {
        outcomes: Default::default(),
        ..index
    }));

    let (status, body) = post_json(
        router(state.clone()),
        "/v1/puzzles/move-or-borrow.001/evaluate",
        optimal_submission(),
    )
    .await;
    assert_eq!(status, 200);
    assert_eq!(body["cached"], false, "no sidecar → live rustc run");
    assert_eq!(
        body["result"]["rank"], "optimal",
        "live compile agrees with precomputed"
    );

    let (_, second) = post_json(
        router(state),
        "/v1/puzzles/move-or-borrow.001/evaluate",
        optimal_submission(),
    )
    .await;
    assert_eq!(
        second["cached"], true,
        "second identical submission hits the live cache"
    );
}
