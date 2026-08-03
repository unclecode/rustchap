---
title: Backend API and data model
status: backlog
sources: []
related:
  - architecture/evaluation.md
  - architecture/ios-app.md
  - roadmap/build-order.md
---

# Backend API and data model

Rust service exposing the puzzle catalogue, evaluation, auth, and progress sync. Lives in
`services/api/`.

> **Agreed design, no code yet.** When implementation lands, add real file paths to `sources:` and
> flip `status` to `shipped`.

## Stack

Rust stable · Tokio · **Axum** (0.8 line) · Serde · SQLx · **PostgreSQL** · **Redis** · Tracing ·
Tower middleware. Deployed as one API service plus a compiler-worker pool (see
[evaluation](evaluation.md)). Puzzle packs served via object storage/CDN eventually.

## Endpoints (v0.1 surface)

```http
GET  /v1/app-config
GET  /v1/packs
GET  /v1/packs/{pack_id}
GET  /v1/puzzles/{puzzle_id}
POST /v1/puzzles/{puzzle_id}/evaluate
POST /v1/progress/sync
GET  /v1/leaderboards/{puzzle_id}     (post-v0.1)
```

Anonymous users operate on a local installation ID; no account is required to play.

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
