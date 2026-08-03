---
title: Backend API and data model
status: living
sources:
  - services/api/src/lib.rs
  - services/api/src/main.rs
  - services/api/src/db.rs
  - services/api/migrations/0001_init.sql
  - tools/dev-db.sh
related:
  - architecture/evaluation.md
  - architecture/ios-app.md
  - roadmap/build-order.md
---

# Backend API and data model

Rust service exposing the puzzle catalogue, evaluation, and (later) auth + progress sync. Lives in
`services/api/`.

## Shipped: catalogue + evaluation API (step 14)

Axum 0.8 + Tokio. `load_content` indexes `content/` at startup (packs, puzzles, outcome
sidecars); `router` exposes:

```http
GET  /v1/app-config                        counts + schema version
GET  /v1/packs                             all pack manifests
GET  /v1/packs/{pack_id}                   pack + full puzzle JSONs
GET  /v1/puzzles/{puzzle_id}               one puzzle
POST /v1/puzzles/{puzzle_id}/evaluate      Submission → {cached, result}
```

`evaluate_submission` answers fastest-first: precomputed sidecar → in-memory live cache
(`AppState.live_cache`, key `puzzle_id:version:ops_hash`) → real compile via
`tokio::task::spawn_blocking(evaluator::evaluate)`. Version mismatch → 409 (`ApiError`
enum maps to status codes). Dev server binds 127.0.0.1:8787 (`--content`, `--port`) — the iOS
Simulator reaches it as plain `http://localhost:8787` (loopback is ATS-exempt); a physical
device needs the Mac's LAN IP instead.

> **In-process evaluation is a deliberate dev-stage decision.** Submissions are only
> `puzzle_id + enumerable operations` — no arbitrary-code surface exists — so the sandboxed
> worker pool (Docker: no network, pinned toolchain, CPU/memory/time limits) is deferred to
> deployment (build-order step 13/28), not built before it's needed.

## Shipped: anonymous identity + durable progress (steps 16-17, 19 server side)

Postgres 17 in Docker (`tools/dev-db.sh`, port 5433, volume `rustchap-pgdata`) + SQLx with
embedded migrations (`db::connect_and_migrate`). `AppState.db` is optional: without a database
the server still serves content and evaluates; identity/progress endpoints return 503.

```http
POST /v1/devices/register        {name?, email?} → {device_id, token}
GET  /v1/devices/me              profile (auth)
PUT  /v1/devices/me              update name/email — COALESCE, never clears (auth)
POST /v1/progress/sync           {records: [...]} → merged full set (auth)
```

- **Identity** (`db.rs`): anonymous device — UUID + bearer token (244 random bits; only the
  SHA-256 hash is stored, `devices.token_hash`). The app keeps the token in the Keychain, which
  survives reinstalls — that's what makes progress recovery work. Name/email optional, never
  required to play. `authenticate` touches `last_seen_at`.
- **Sync** (`db::merge` + `sync_progress`): plan merge rules — newer puzzle_version wins
  wholesale; same version: solved beats unsolved, better rank beats worse, earliest first-solve,
  max attempt count. An empty push returns the server's full set (reinstall recovery).
- **Attempts**: authenticated `POST /evaluate` calls log a `puzzle_attempts` row
  (fire-and-forget) — operations, status, rank, metrics, cached — fuel for difficulty analysis.
- Verified by `tests/identity_sync.rs` against live Postgres (skips without DATABASE_URL):
  register → 401 unauth → optimal push → weaker-sync-no-downgrade → empty-push recovery →
  profile COALESCE semantics → attempt row landed.

## Later

Sign in with Apple as account linking on top of device identity; Redis if the in-process caches
outgrow one instance; leaderboards post-v0.1.

## Authentication — Sign in with Apple

```text
iPhone requests Apple authentication
→ Apple returns identity token
→ app sends token to API
→ API verifies token
→ API creates or finds user
→ API issues our access and refresh tokens
```

> **Store Apple's stable user identifier, not the email.** Users may hide their real email; the
> identifier is the durable key. Support from day one: reinstall, device change, sign-out/in, token
> expiration, Apple credential revocation, offline launch, conflicting local vs cloud progress,
> puzzle version changes.

## Database tables (minimum)

```text
users · devices · auth_sessions · puzzle_progress · puzzle_attempts · user_settings · content_versions
```

`puzzle_progress` holds the current best per (user, puzzle): status, `best_primary_score`,
`best_secondary_score`, `attempt_count`, `first_solved_at`, `best_solved_at`.

`puzzle_attempts` records every meaningful submission: operations, compiler_result, score,
duration, created_at. Attempts feed difficulty analysis, common-wrong-answer mining, hint
improvement, broken-puzzle detection, and replay measurement.

Progress merge rules (server authoritative for evaluated scores):

```text
Solved beats unsolved
Better score beats worse score
Server-verified beats local-only
Newest attempt does not automatically beat best attempt
```

## Telemetry

Product events only, no surveillance noise: `puzzle_opened`, `answer_modified`,
`evaluation_requested`, `compile_failed`, `puzzle_solved`, `better_score_achieved`, `hint_opened`,
`explanation_opened`, `puzzle_abandoned`, `next_puzzle_opened`. Critical derived metrics: completion
rate, **retry rate after first success** (the headline signal), time-to-first-success, hint usage,
next-puzzle continuation, seven-day return, abandonment hotspots.

## Operational baseline (production checklist)

Backups, token rotation, rate limiting, crash reporting, compiler-worker alerts, structured
logs/error reporting, privacy policy, terms, account deletion, support contact. Staging environment
(`api-staging`, compiler-staging, managed Postgres/Redis) precedes production; infrastructure as
code from the start; production deploys stay manual initially.
