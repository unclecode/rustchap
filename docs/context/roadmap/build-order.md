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
- [ ] 7. Hand-author five representative puzzles — one per track, deliberately covering: a compile
      failure, multiple valid answers, a measurable optimal answer, a Clippy-based result, a
      runtime-test answer

## Phase 3 — iPhone interaction prototype
- [ ] 8. SwiftUI app shell (Launch → Puzzle → Result → Retry/Next; no auth, no backend, 5 bundled puzzles)
- [ ] 9. Semantic code renderer (CodeSurface — the hardest UI component)
- [ ] 10. All four interaction types against the five local puzzles
- [ ] 11. Install via Xcode, dogfood — **gate: is the loop addictive?**

## Phase 4 — evaluation
- [ ] 12. Rust evaluator as a local CLI (engine already shipped as the `crates/evaluator` library
      with step 6; only a thin CLI wrapper remains)
- [ ] 13. Isolated compiler workers (Docker, no network, fixed toolchain)
- [ ] 14. Axum API (`services/api`)
- [ ] 15. Connect iPhone to remote evaluation

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
