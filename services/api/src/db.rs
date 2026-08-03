//! Device identity + durable progress (build-order steps 16-17, 19).
//!
//! Identity is an anonymous device: `register` mints a UUID + bearer token
//! (stored hashed); the app keeps the token in the Keychain, which survives
//! reinstalls — that is what makes progress recovery work. Name/email are
//! optional profile fields, never required to play.

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn connect_and_migrate(url: &str) -> Result<PgPool> {
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(8)
        .connect(url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    Ok(pool)
}

fn hash_token(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

// MARK: devices

#[derive(Debug, Serialize)]
pub struct RegisteredDevice {
    pub device_id: Uuid,
    pub token: String,
}

pub async fn register_device(
    pool: &PgPool,
    name: Option<&str>,
    email: Option<&str>,
) -> Result<RegisteredDevice> {
    let device_id = Uuid::new_v4();
    // 2 × v4 = 244 random bits, hex-encoded; only the hash is stored.
    let token = format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple());
    sqlx::query("INSERT INTO devices (id, token_hash, name, email) VALUES ($1, $2, $3, $4)")
        .bind(device_id)
        .bind(hash_token(&token))
        .bind(name)
        .bind(email)
        .execute(pool)
        .await?;
    Ok(RegisteredDevice { device_id, token })
}

/// Bearer-token lookup; touches `last_seen_at`. None = unknown token.
pub async fn authenticate(pool: &PgPool, token: &str) -> Result<Option<Uuid>> {
    let row: Option<(Uuid,)> = sqlx::query_as(
        "UPDATE devices SET last_seen_at = now() WHERE token_hash = $1 RETURNING id",
    )
    .bind(hash_token(token))
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.0))
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct DeviceProfile {
    pub device_id: Uuid,
    pub name: Option<String>,
    pub email: Option<String>,
    pub created_at: DateTime<Utc>,
}

pub async fn get_profile(pool: &PgPool, device_id: Uuid) -> Result<Option<DeviceProfile>> {
    Ok(
        sqlx::query_as(
            "SELECT id AS device_id, name, email, created_at FROM devices WHERE id = $1",
        )
        .bind(device_id)
        .fetch_optional(pool)
        .await?,
    )
}

pub async fn update_profile(
    pool: &PgPool,
    device_id: Uuid,
    name: Option<&str>,
    email: Option<&str>,
) -> Result<()> {
    sqlx::query(
        "UPDATE devices SET name = COALESCE($2, name), email = COALESCE($3, email) WHERE id = $1",
    )
    .bind(device_id)
    .bind(name)
    .bind(email)
    .execute(pool)
    .await?;
    Ok(())
}

// MARK: progress sync

/// Wire + storage shape of one puzzle's progress. The same struct goes both
/// directions in `/v1/progress/sync`.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ProgressRecord {
    pub puzzle_id: String,
    pub puzzle_version: i32,
    pub solved: bool,
    pub best_rank: Option<String>,
    pub best_metrics: serde_json::Value,
    pub attempt_count: i32,
    pub first_solved_at: Option<DateTime<Utc>>,
    pub best_solved_at: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
}

fn rank_order(rank: Option<&str>) -> i32 {
    match rank {
        Some("optimal") => 3,
        Some("fluent") => 2,
        Some("solved") => 1,
        _ => 0,
    }
}

/// Plan merge rules: a newer puzzle version wins wholesale (old bests are
/// meaningless); same version — solved beats unsolved, better rank beats
/// worse, earliest first-solve, max attempt count.
pub fn merge(server: &ProgressRecord, client: &ProgressRecord) -> ProgressRecord {
    if client.puzzle_version != server.puzzle_version {
        let (newer, older) = if client.puzzle_version > server.puzzle_version {
            (client, server)
        } else {
            (server, client)
        };
        let mut merged = newer.clone();
        merged.attempt_count = newer.attempt_count.max(older.attempt_count);
        return merged;
    }
    let base = if rank_order(client.best_rank.as_deref()) > rank_order(server.best_rank.as_deref())
    {
        client
    } else {
        server
    };
    let mut merged = base.clone();
    merged.solved = server.solved || client.solved;
    merged.attempt_count = server.attempt_count.max(client.attempt_count);
    merged.first_solved_at = match (server.first_solved_at, client.first_solved_at) {
        (Some(a), Some(b)) => Some(a.min(b)),
        (a, b) => a.or(b),
    };
    merged.updated_at = Utc::now();
    merged
}

pub async fn sync_progress(
    pool: &PgPool,
    device_id: Uuid,
    client_records: &[ProgressRecord],
) -> Result<Vec<ProgressRecord>> {
    for client in client_records {
        let server: Option<ProgressRecord> = sqlx::query_as(
            "SELECT puzzle_id, puzzle_version, solved, best_rank, best_metrics,
                    attempt_count, first_solved_at, best_solved_at, updated_at
             FROM puzzle_progress WHERE device_id = $1 AND puzzle_id = $2",
        )
        .bind(device_id)
        .bind(&client.puzzle_id)
        .fetch_optional(pool)
        .await?;

        let merged = match &server {
            Some(server) => merge(server, client),
            None => client.clone(),
        };
        sqlx::query(
            "INSERT INTO puzzle_progress
                (device_id, puzzle_id, puzzle_version, solved, best_rank, best_metrics,
                 attempt_count, first_solved_at, best_solved_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
             ON CONFLICT (device_id, puzzle_id) DO UPDATE SET
                puzzle_version = EXCLUDED.puzzle_version,
                solved = EXCLUDED.solved,
                best_rank = EXCLUDED.best_rank,
                best_metrics = EXCLUDED.best_metrics,
                attempt_count = EXCLUDED.attempt_count,
                first_solved_at = EXCLUDED.first_solved_at,
                best_solved_at = EXCLUDED.best_solved_at,
                updated_at = now()",
        )
        .bind(device_id)
        .bind(&merged.puzzle_id)
        .bind(merged.puzzle_version)
        .bind(merged.solved)
        .bind(&merged.best_rank)
        .bind(&merged.best_metrics)
        .bind(merged.attempt_count)
        .bind(merged.first_solved_at)
        .bind(merged.best_solved_at)
        .execute(pool)
        .await?;
    }

    Ok(sqlx::query_as(
        "SELECT puzzle_id, puzzle_version, solved, best_rank, best_metrics,
                attempt_count, first_solved_at, best_solved_at, updated_at
         FROM puzzle_progress WHERE device_id = $1 ORDER BY puzzle_id",
    )
    .bind(device_id)
    .fetch_all(pool)
    .await?)
}

// MARK: attempts

#[allow(clippy::too_many_arguments)]
pub async fn record_attempt(
    pool: &PgPool,
    device_id: Uuid,
    puzzle_id: &str,
    puzzle_version: i32,
    operations: serde_json::Value,
    status: &str,
    rank: Option<&str>,
    metrics: serde_json::Value,
    cached: bool,
) -> Result<()> {
    sqlx::query(
        "INSERT INTO puzzle_attempts
            (device_id, puzzle_id, puzzle_version, operations, status, rank, metrics, cached)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(device_id)
    .bind(puzzle_id)
    .bind(puzzle_version)
    .bind(operations)
    .bind(status)
    .bind(rank)
    .bind(metrics)
    .bind(cached)
    .execute(pool)
    .await?;
    Ok(())
}
