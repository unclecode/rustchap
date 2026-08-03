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

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, RwLock};

use anyhow::{Context, Result};
use axum::extract::{Path as UrlPath, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use evaluator::Toolchain;
use puzzle_schema::{EvalResult, Outcomes, Pack, Puzzle, Submission, ops_hash};
use serde::Serialize;

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
    /// On-demand compilation results, keyed by `puzzle_id + version + ops_hash`.
    live_cache: RwLock<HashMap<String, EvalResult>>,
}

impl AppState {
    pub fn new(index: ContentIndex) -> Self {
        AppState {
            index,
            toolchain: Toolchain::default(),
            live_cache: RwLock::new(HashMap::new()),
        }
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
        .with_state(state)
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

    // 1. Precomputed outcomes.
    if let Some(sidecar) = state.index.outcomes.get(&puzzle_id)
        && let Some(result) = sidecar.outcomes.get(&hash)
    {
        return Ok(Json(EvaluateResponse {
            cached: true,
            result: result.clone(),
        }));
    }

    // 2. Live cache.
    let cache_key = format!("{}:{}:{}", puzzle.id, puzzle.version, hash);
    if let Some(result) = state.live_cache.read().expect("cache lock").get(&cache_key) {
        return Ok(Json(EvaluateResponse {
            cached: true,
            result: result.clone(),
        }));
    }

    // 3. Live compile on a blocking thread.
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
    Ok(Json(EvaluateResponse {
        cached: false,
        result,
    }))
}

pub enum ApiError {
    NotFound,
    BadRequest(&'static str),
    VersionMismatch,
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
            ApiError::Internal(m) => (StatusCode::INTERNAL_SERVER_ERROR, m),
        };
        (status, Json(serde_json::json!({ "error": message }))).into_response()
    }
}
