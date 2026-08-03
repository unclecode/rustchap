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
- [ ] 16. Sign in with Apple
- [ ] 17. PostgreSQL user/progress model
- [ ] 18. SwiftData offline state
- [ ] 19. Cloud synchronization + identity edge cases

## Phase 6 — the real question bank
- [ ] 20. Content authoring workflow (`tools/`)
- [ ] 21. Ingest open-source material (transform, never import)
- [ ] 22. Complete the first 40 puzzles
- [ ] 23. Progression analysis pass

## Phase 7 — product finishing
- [ ] 24. Track-map navigation
- [ ] 25. Result levels (Solved / Fluent / Optimal)
- [ ] 26. Profile and progress screens
- [ ] 27. Telemetry

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
