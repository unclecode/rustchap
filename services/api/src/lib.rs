//! # api — RustChap backend (build-order step 14)
//!
//! Serves the puzzle catalogue and evaluates submissions. Evaluation strategy,
//! fastest first:
//!
//! 1. **Precomputed outcomes** (the linter's sidecars, loaded at startup) —
//!    answers every enumerable submission without compiling.
//! 2. **Live cache** — results of previous on-demand compilations.
//! 3. **Live compile** — the same `evaluator` engine the linter uses, run on a
//!    blocking thread. In-process is sound here because submissions are only
//!    `puzzle_id + enumerable operations`; there is no arbitrary-code surface.
//!    Container isolation arrives with deployment, not before.

pub mod db;

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use anyhow::{Context, Result};
use axum::extract::{Path as UrlPath, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use evaluator::Toolchain;
use puzzle_schema::{EvalResult, Outcomes, Pack, Puzzle, Submission, ops_hash};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub struct ContentIndex {
    pub packs: Vec<Pack>,
    pub puzzles: HashMap<String, Puzzle>,
    pub outcomes: HashMap<String, Outcomes>,
}

#[derive(serde::Deserialize)]
struct PackIndex {
    #[allow(dead_code)]
    schema_version: u32,
    order: Vec<String>,
}

/// Load packs, puzzles, and outcome sidecars from a content root
/// (`content/` in the repo: `packs/<track>/{pack.json,puzzles,outcomes}`).
/// Pack order comes from `packs/index.json` — the curriculum sequence —
/// with any unlisted pack directories appended alphabetically.
pub fn load_content(root: &Path) -> Result<ContentIndex> {
    let packs_dir = root.join("packs");
    let mut packs = Vec::new();
    let mut puzzles = HashMap::new();
    let mut outcomes = HashMap::new();

    let mut dirs: Vec<_> = std::fs::read_dir(&packs_dir)
        .with_context(|| format!("reading {}", packs_dir.display()))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    dirs.sort();

    let index_path = packs_dir.join("index.json");
    if index_path.exists() {
        let index: PackIndex = serde_json::from_str(&std::fs::read_to_string(&index_path)?)
            .with_context(|| format!("parsing {}", index_path.display()))?;
        let position = |dir: &std::path::PathBuf| {
            let name = dir
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned();
            index
                .order
                .iter()
                .position(|t| *t == name)
                .unwrap_or(usize::MAX)
        };
        dirs.sort_by_key(|dir| (position(dir), dir.clone()));
    }

    for dir in dirs {
        let pack: Pack = serde_json::from_str(
            &std::fs::read_to_string(dir.join("pack.json"))
                .with_context(|| format!("reading {}/pack.json", dir.display()))?,
        )?;
        for puzzle_id in &pack.order {
            let puzzle: Puzzle = serde_json::from_str(&std::fs::read_to_string(
                dir.join(format!("puzzles/{puzzle_id}.json")),
            )?)
            .with_context(|| format!("parsing puzzle {puzzle_id}"))?;
            puzzles.insert(puzzle_id.clone(), puzzle);

            let sidecar_path = dir.join(format!("outcomes/{puzzle_id}.json"));
            if let Ok(text) = std::fs::read_to_string(&sidecar_path) {
                let sidecar: Outcomes = serde_json::from_str(&text)
                    .with_context(|| format!("parsing outcomes for {puzzle_id}"))?;
                outcomes.insert(puzzle_id.clone(), sidecar);
            }
        }
        packs.push(pack);
    }
    Ok(ContentIndex {
        packs,
        puzzles,
        outcomes,
    })
}

pub struct AppState {
    pub index: ContentIndex,
    pub toolchain: Toolchain,
    /// Present when Postgres is reachable; identity/progress endpoints
    /// return 503 without it, content/evaluation work regardless.
    pub db: Option<sqlx::PgPool>,
    /// On-demand compilation results, keyed by `puzzle_id + version + ops_hash`.
    live_cache: RwLock<HashMap<String, EvalResult>>,
}

impl AppState {
    pub fn new(index: ContentIndex) -> Self {
        AppState {
            index,
            toolchain: Toolchain::default(),
            db: None,
            live_cache: RwLock::new(HashMap::new()),
        }
    }

    pub fn with_db(mut self, pool: sqlx::PgPool) -> Self {
        self.db = Some(pool);
        self
    }
}

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/v1/app-config", get(app_config))
        .route("/v1/packs", get(list_packs))
        .route("/v1/packs/{pack_id}", get(get_pack))
        .route("/v1/puzzles/{puzzle_id}", get(get_puzzle))
        .route(
            "/v1/puzzles/{puzzle_id}/evaluate",
            post(evaluate_submission),
        )
        .route("/v1/devices/register", post(register_device))
        .route("/v1/devices/me", get(get_profile).put(update_profile))
        .route("/v1/progress/sync", post(sync_progress))
        .with_state(state)
}

// MARK: - Device auth (anonymous bearer token)

fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(header::AUTHORIZATION)?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")
}

/// Resolve the calling device, or the reason it can't be resolved.
async fn require_device(state: &AppState, headers: &HeaderMap) -> Result<Uuid, ApiError> {
    let Some(pool) = &state.db else {
        return Err(ApiError::NoDatabase);
    };
    let Some(token) = bearer_token(headers) else {
        return Err(ApiError::Unauthorized);
    };
    match db::authenticate(pool, token).await {
        Ok(Some(device_id)) => Ok(device_id),
        Ok(None) => Err(ApiError::Unauthorized),
        Err(e) => {
            tracing::error!("auth lookup failed: {e}");
            Err(ApiError::Internal("auth lookup failed"))
        }
    }
}

#[derive(Deserialize, Default)]
struct ProfileBody {
    name: Option<String>,
    email: Option<String>,
}

async fn register_device(
    State(state): State<Arc<AppState>>,
    body: Option<Json<ProfileBody>>,
) -> Result<Json<db::RegisteredDevice>, ApiError> {
    let Some(pool) = &state.db else {
        return Err(ApiError::NoDatabase);
    };
    let body = body.map(|Json(b)| b).unwrap_or_default();
    db::register_device(pool, body.name.as_deref(), body.email.as_deref())
        .await
        .map(Json)
        .map_err(|e| {
            tracing::error!("register failed: {e}");
            ApiError::Internal("register failed")
        })
}

async fn get_profile(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<db::DeviceProfile>, ApiError> {
    let device_id = require_device(&state, &headers).await?;
    let pool = state.db.as_ref().expect("checked by require_device");
    db::get_profile(pool, device_id)
        .await
        .map_err(|e| {
            tracing::error!("profile fetch failed: {e}");
            ApiError::Internal("profile fetch failed")
        })?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn update_profile(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<ProfileBody>,
) -> Result<StatusCode, ApiError> {
    let device_id = require_device(&state, &headers).await?;
    let pool = state.db.as_ref().expect("checked by require_device");
    db::update_profile(pool, device_id, body.name.as_deref(), body.email.as_deref())
        .await
        .map(|_| StatusCode::NO_CONTENT)
        .map_err(|e| {
            tracing::error!("profile update failed: {e}");
            ApiError::Internal("profile update failed")
        })
}

#[derive(Serialize, Deserialize)]
struct SyncBody {
    records: Vec<db::ProgressRecord>,
}

async fn sync_progress(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<SyncBody>,
) -> Result<Json<SyncBody>, ApiError> {
    let device_id = require_device(&state, &headers).await?;
    let pool = state.db.as_ref().expect("checked by require_device");
    db::sync_progress(pool, device_id, &body.records)
        .await
        .map(|records| Json(SyncBody { records }))
        .map_err(|e| {
            tracing::error!("sync failed: {e}");
            ApiError::Internal("sync failed")
        })
}

// MARK-style sections keep handler order matching the route table above.

async fn app_config(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "schema_version": 1,
        "packs": state.index.packs.len(),
        "puzzles": state.index.puzzles.len(),
    }))
}

async fn list_packs(State(state): State<Arc<AppState>>) -> Json<Vec<Pack>> {
    Json(state.index.packs.clone())
}

#[derive(Serialize)]
struct PackDetail {
    #[serde(flatten)]
    pack: Pack,
    puzzles: Vec<Puzzle>,
}

async fn get_pack(
    State(state): State<Arc<AppState>>,
    UrlPath(pack_id): UrlPath<String>,
) -> Result<Json<PackDetail>, ApiError> {
    let pack = state
        .index
        .packs
        .iter()
        .find(|p| p.id == pack_id)
        .ok_or(ApiError::NotFound)?;
    let puzzles = pack
        .order
        .iter()
        .filter_map(|id| state.index.puzzles.get(id).cloned())
        .collect();
    Ok(Json(PackDetail {
        pack: pack.clone(),
        puzzles,
    }))
}

async fn get_puzzle(
    State(state): State<Arc<AppState>>,
    UrlPath(puzzle_id): UrlPath<String>,
) -> Result<Json<Puzzle>, ApiError> {
    state
        .index
        .puzzles
        .get(&puzzle_id)
        .cloned()
        .map(Json)
        .ok_or(ApiError::NotFound)
}

#[derive(Serialize)]
pub struct EvaluateResponse {
    /// True when the verdict came from precomputed outcomes or the live cache
    /// (no compiler ran for this request).
    pub cached: bool,
    pub result: EvalResult,
}

async fn evaluate_submission(
    State(state): State<Arc<AppState>>,
    UrlPath(puzzle_id): UrlPath<String>,
    headers: HeaderMap,
    Json(submission): Json<Submission>,
) -> Result<Json<EvaluateResponse>, ApiError> {
    let puzzle = state
        .index
        .puzzles
        .get(&puzzle_id)
        .ok_or(ApiError::NotFound)?;
    if submission.puzzle_id != puzzle.id {
        return Err(ApiError::BadRequest("submission puzzle_id mismatch"));
    }
    if submission.puzzle_version != puzzle.version {
        return Err(ApiError::VersionMismatch);
    }

    let hash = ops_hash(&submission.operations);
    let cache_key = format!("{}:{}:{}", puzzle.id, puzzle.version, hash);

    // Fastest first: precomputed sidecar → live cache → real compile.
    let (result, cached) = if let Some(result) = state
        .index
        .outcomes
        .get(&puzzle_id)
        .and_then(|sidecar| sidecar.outcomes.get(&hash))
    {
        (result.clone(), true)
    } else if let Some(result) = state.live_cache.read().expect("cache lock").get(&cache_key) {
        (result.clone(), true)
    } else {
        let puzzle_clone = puzzle.clone();
        let toolchain = state.toolchain.clone();
        let operations = submission.operations.clone();
        let result = tokio::task::spawn_blocking(move || {
            evaluator::evaluate(&puzzle_clone, &operations, &toolchain)
        })
        .await
        .map_err(|_| ApiError::Internal("evaluation task panicked"))?
        .map_err(|e| {
            tracing::error!("evaluation failed: {e}");
            ApiError::Internal("evaluation failed")
        })?;
        state
            .live_cache
            .write()
            .expect("cache lock")
            .insert(cache_key, result.clone());
        (result, false)
    };

    // Authenticated submissions become attempt rows (fire-and-forget) —
    // fuel for difficulty analysis and replay measurement.
    if let Some(pool) = state.db.clone()
        && let Ok(device_id) = require_device(&state, &headers).await
    {
        let puzzle_id = puzzle.id.clone();
        let puzzle_version = puzzle.version as i32;
        let operations = serde_json::to_value(&submission.operations).unwrap_or_default();
        let status = serde_json::to_value(result.status)
            .ok()
            .and_then(|v| v.as_str().map(String::from))
            .unwrap_or_default();
        let rank = result
            .rank
            .and_then(|r| serde_json::to_value(r).ok())
            .and_then(|v| v.as_str().map(String::from));
        let metrics = serde_json::to_value(&result.metrics).unwrap_or_default();
        tokio::spawn(async move {
            if let Err(e) = db::record_attempt(
                &pool,
                device_id,
                &puzzle_id,
                puzzle_version,
                operations,
                &status,
                rank.as_deref(),
                metrics,
                cached,
            )
            .await
            {
                tracing::warn!("attempt log failed: {e}");
            }
        });
    }

    Ok(Json(EvaluateResponse { cached, result }))
}

pub enum ApiError {
    NotFound,
    BadRequest(&'static str),
    VersionMismatch,
    Unauthorized,
    NoDatabase,
    Internal(&'static str),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            ApiError::NotFound => (StatusCode::NOT_FOUND, "not found"),
            ApiError::BadRequest(m) => (StatusCode::BAD_REQUEST, m),
            ApiError::VersionMismatch => (
                StatusCode::CONFLICT,
                "puzzle version mismatch — refresh content",
            ),
            ApiError::Unauthorized => (StatusCode::UNAUTHORIZED, "unknown or missing device token"),
            ApiError::NoDatabase => (
                StatusCode::SERVICE_UNAVAILABLE,
                "identity/progress requires the database",
            ),
            ApiError::Internal(m) => (StatusCode::INTERNAL_SERVER_ERROR, m),
        };
        (status, Json(serde_json::json!({ "error": message }))).into_response()
    }
}
