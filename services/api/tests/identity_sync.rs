//! Identity + progress round trip against a real Postgres. Skips silently when
//! DATABASE_URL is not set (CI without a database still passes).

use std::path::Path;
use std::sync::Arc;

use api::{AppState, load_content, router};
use http_body_util::BodyExt;
use serde_json::json;
use tower::ServiceExt;

fn content_root() -> &'static Path {
    Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../../content"))
}

async fn request(
    app: axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<serde_json::Value>,
) -> (u16, serde_json::Value) {
    let mut builder = axum::http::Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    let request = if let Some(body) = body {
        builder
            .header("content-type", "application/json")
            .body(axum::body::Body::from(body.to_string()))
            .unwrap()
    } else {
        builder.body(axum::body::Body::empty()).unwrap()
    };
    let response = app.oneshot(request).await.unwrap();
    let status = response.status().as_u16();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let value = if bytes.is_empty() {
        json!(null)
    } else {
        serde_json::from_slice(&bytes).unwrap()
    };
    (status, value)
}

fn progress_record(rank: &str, attempts: i32) -> serde_json::Value {
    json!({
        "puzzle_id": "move-or-borrow.001",
        "puzzle_version": 1,
        "solved": true,
        "best_rank": rank,
        "best_metrics": { "clone_count": 0, "token_edits": 2 },
        "attempt_count": attempts,
        "first_solved_at": "2026-08-03T10:00:00Z",
        "best_solved_at": "2026-08-03T10:05:00Z",
        "updated_at": "2026-08-03T10:05:00Z"
    })
}

#[tokio::test]
async fn register_sync_merge_and_recover() {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("skipped: DATABASE_URL not set");
        return;
    };
    let Ok(pool) = api::db::connect_and_migrate(&url).await else {
        eprintln!("skipped: database unreachable");
        return;
    };
    let state =
        Arc::new(AppState::new(load_content(content_root()).unwrap()).with_db(pool.clone()));

    // Register with an optional name; email left blank.
    let (status, registered) = request(
        router(state.clone()),
        "POST",
        "/v1/devices/register",
        None,
        Some(json!({ "name": "Tester" })),
    )
    .await;
    assert_eq!(status, 200);
    let token = registered["token"].as_str().unwrap().to_string();

    // No token → 401.
    let (status, _) = request(
        router(state.clone()),
        "POST",
        "/v1/progress/sync",
        None,
        Some(json!({ "records": [] })),
    )
    .await;
    assert_eq!(status, 401);

    // Push an optimal result.
    let (status, body) = request(
        router(state.clone()),
        "POST",
        "/v1/progress/sync",
        Some(&token),
        Some(json!({ "records": [progress_record("optimal", 3)] })),
    )
    .await;
    assert_eq!(status, 200);
    assert_eq!(body["records"][0]["best_rank"], "optimal");

    // A weaker later sync must NOT downgrade the stored best (merge rules),
    // but the higher attempt count wins.
    let (_, body) = request(
        router(state.clone()),
        "POST",
        "/v1/progress/sync",
        Some(&token),
        Some(json!({ "records": [progress_record("solved", 9)] })),
    )
    .await;
    assert_eq!(body["records"][0]["best_rank"], "optimal");
    assert_eq!(body["records"][0]["attempt_count"], 9);

    // Reinstall simulation: empty push returns the server's copy.
    let (_, body) = request(
        router(state.clone()),
        "POST",
        "/v1/progress/sync",
        Some(&token),
        Some(json!({ "records": [] })),
    )
    .await;
    assert_eq!(body["records"].as_array().unwrap().len(), 1);
    assert_eq!(body["records"][0]["best_rank"], "optimal");

    // Profile: name from registration, email added later.
    let (_, profile) = request(
        router(state.clone()),
        "GET",
        "/v1/devices/me",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(profile["name"], "Tester");
    let (status, _) = request(
        router(state.clone()),
        "PUT",
        "/v1/devices/me",
        Some(&token),
        Some(json!({ "email": "tester@example.com" })),
    )
    .await;
    assert_eq!(status, 204);
    let (_, profile) = request(
        router(state.clone()),
        "GET",
        "/v1/devices/me",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(profile["email"], "tester@example.com");
    assert_eq!(
        profile["name"], "Tester",
        "PUT with only email must not clear name"
    );

    // An authenticated evaluate logs an attempt row.
    let device_id: uuid::Uuid = registered["device_id"].as_str().unwrap().parse().unwrap();
    let (status, _) = request(
        router(state.clone()),
        "POST",
        "/v1/puzzles/move-or-borrow.001/evaluate",
        Some(&token),
        Some(json!({
            "puzzle_id": "move-or-borrow.001",
            "puzzle_version": 1,
            "operations": [
                { "op": "select", "slot_id": "arg", "choice_id": "c2" },
                { "op": "select", "slot_id": "param_ty", "choice_id": "t3" }
            ]
        })),
    )
    .await;
    assert_eq!(status, 200);
    tokio::time::sleep(std::time::Duration::from_millis(400)).await; // fire-and-forget insert
    let (count,): (i64,) =
        sqlx::query_as("SELECT count(*) FROM puzzle_attempts WHERE device_id = $1")
            .bind(device_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(count, 1, "authenticated evaluate records an attempt");
}
