---
title: Build order
status: living
sources: []
related:
  - roadmap/v0.1-scope.md
  - architecture/evaluation.md
  - architecture/ios-app.md
---

# Build order

Vertical slices — at every stage something is usable on the phone. Never "finish backend, then app,
then content." Update the checkboxes as steps complete; this fragment is the living progress state.

## Phase 1 — product contract
- [x] 1. Freeze v0.1 ([v0.1-scope](v0.1-scope.md))
- [x] 2. Define the five tracks
- [x] 3. Define the four interaction types

## Phase 2 — puzzle engine before the full app
- [x] 4. Create the monorepo (skeleton created; name: RustChap)
- [x] 5. Design the puzzle JSON schema (`schemas/puzzle.schema.json` + `pack` + `outcomes`;
      enforced by `crates/puzzle-schema` — types, validation, reconstruction, hashing, enumeration)
- [x] 6. Build the puzzle linter (`tools/puzzle-linter`: structure checks + full-space evaluation
      via `crates/evaluator` + outcomes sidecar generation + `--check` CI mode)
- [x] 7. Hand-author five representative puzzles — one per track (`content/packs/*/`), covering: a
      compile failure, multiple valid answers, a measurable optimal answer, a Clippy-based result, a
      runtime-test answer; all 72 submissions evaluated, outcomes sidecars generated + `--check` clean

## Phase 3 — iPhone interaction prototype
- [x] 8. SwiftUI app shell (`apps/ios/`: Launch → Track list → Puzzle → Result → Retry/Next; no
      auth, no backend; bundles `content/packs` as a folder reference; offline evaluation via
      Swift ops-hash byte-matched to Rust against the outcomes sidecars)
- [x] 9. Semantic code renderer (`PuzzleUI/`: RustLexer + CodeSurface — highlighted token lines,
      horizontal scroll, inline SlotChips with error highlighting, ChoiceTray)
- [x] 10. All four interaction types against the five local puzzles (slot chips, block reorder,
      candidate cards; rank ladder + You-vs-Best score in ResultView)
- [~] 11. Formal multi-day dogfood gate waived (2026-08-03) — continuous dogfooding via simulator
      instead; physical-device install still pending a signing team in Xcode

## Phase 4 — evaluation
- [x] 12. Rust evaluator as a local CLI (`evaluator/src/bin/evaluate.rs`)
- [ ] 13. Isolated compiler workers — deferred to deployment (in-process evaluation is sound while
      submissions are enumerable operations only; see evaluation fragment)
- [x] 14. Axum API (`services/api`: catalogue + evaluate with sidecar → cache → live-compile
      layering; localhost:8787 dev server; router tests incl. live-compile path)
- [x] 15. Connect iPhone to remote evaluation — **Milestone 2**: server-first content + evaluation
      with offline fallback; result sheet shows the verdict source; pack order served from
      `content/packs/index.json`

## Phase 5 — authentication and durable progress
- [x] 16. Identity — anonymous device registration (`/v1/devices/register`, hashed bearer token,
      optional name/email profile); Sign in with Apple later as account linking
- [x] 17. PostgreSQL user/progress model (Postgres 17 via Docker `tools/dev-db.sh` + SQLx
      migrations: devices, puzzle_progress, puzzle_attempts)
- [x] 18. SwiftData offline state (`ProgressStore.swift`: per-puzzle bests + attempts with merge
      rules; track-list badges; verified across cold relaunch)
- [x] 19. Cloud synchronization — **Milestone 3**: Keychain identity + SyncService with 401
      self-heal + profile sheet; verified full uninstall → reinstall → progress restored from
      server with no duplicate registration

## Phase 6 — the real question bank (reframed 2026-08-03: ingestion, not hand-authoring)
- [x] 20a. Deck restructure — Euclidea two-level model: 12 named decks (5 with content, 7 planned
      "Soon"), sequential unlock (solve-all), deck home screen + deck detail + deck-complete flow
- [x] 20b. Authoring workflow — no authoring UI (decision); linter is the backbone, `--summary`
      added for outcome-distribution review
- [x] 21. Ingestion pipeline: `tools/fetch-sources.sh` (rustlings + exercism → bank/sources,
      gitignored) + `tools/catalog-sources.py` (candidates → suggested decks, bank/catalog.json)
- [x] 22. Fill the decks from the bank — batches 1–6: **all 15 decks alive, 61 puzzles,
      364 verified submissions**; deck deepening continues as ongoing content rhythm
- [x] 23. Progression analysis — `tools/audit-progression.py`: difficulty ramps, guessability
      as optimal-rate (the game is rank-seeking), allowlisted deliberate ties, opener-prereq
      check; runs clean; two coin-flip puzzles widened as a result

**Phase 6 complete (2026-08-04).**

## Phase 7 — product finishing
- [x] 24. Navigation — the deck home IS the map; garnish added: "Continue" chip on the current
      deck, deck-complete celebration ("the next chest is open") on the result sheet
- [x] 25. Result levels — rank ladder, You-vs-Best, persisted bests (done earlier)
- [x] 26. Profile & progress — dashboard in the profile sheet: solved/optimal/attempt stats,
      strongest concepts, needs-more-work concepts (computed on-device from SwiftData records ×
      puzzle concepts); no XP/coins/badges, per the plan
- [~] 27. Telemetry — server-side attempt logging exists (operations, verdict, rank, cached);
      app-side event telemetry (hint_opened, abandoned, replay) DEFERRED until pre-TestFlight —
      measuring a single user's own behavior has no value

**Phase 7 complete (2026-08-04); 27's remainder deliberately parked.**

## Phase 8 — deployment
- [ ] 28. Staging infrastructure (IaC from the start)
- [ ] 29. CI/CD (Swift tests, Rust tests, schema validation, compile all reference solutions +
      alternatives, score reproducibility, container builds)
- [ ] 30. Multi-day physical-device dogfood (poor connection, airplane mode, one-handed, dark mode,
      interruptions, kill-during-evaluation, sign-out/reinstall, large text, rapid submissions)
- [ ] 31. Internal TestFlight (~6 chosen testers, not a noisy public beta)
- [ ] 32. Fix content before adding features
- [ ] 33. Public TestFlight + selective open-sourcing
- [ ] 34. Production deployment + App Store release (checklist in [backend](../architecture/backend.md))

## Sequencing rules

- Milestones gate scale: 5 puzzles must be fun before 40 exist ([v0.1-scope](v0.1-scope.md)).
- The linter (6) precedes any UI; the evaluator CLI (12) precedes the API (14).
- Auth (16) comes after the core loop works but before content expansion.
- The first beta fixes content and interaction before any new features.
