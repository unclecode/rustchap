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

## Phase 8 — deployment (user-chosen order: device first, then review, then the rest)
- [x] Repo: private GitHub https://github.com/unclecode/rustchap (pushed 2026-08-04, full history)
- [x] 30-first. Physical-device install DONE (2026-08-04) — UDID registered manually on the
      portal (the `-allowProvisioningDeviceRegistration` path never worked), fresh team profile
      embeds the device, app installed + launched headlessly via devicectl on iPhone-17-Pro-Max
      (paid team TPP52TWEWR, no 7-day expiry).
- [x] User review round BATCH 1 COMMITTED (2026-08-04). Shipped: (a) ghost-selections
      state-leak bug found on-device and fixed (RCA in [ios-app](../architecture/ios-app.md));
      (b) `lesson` interaction type end-to-end (contract → linter → audit → app); (c) 20
      lectures — every deck opens with one + 4 mid-deck, plain-English style rules recorded in
      [curriculum](../foundation/curriculum.md), em-dash sweep over all content; (d) on-device
      AI tutor (Foundation Models; spike: raw model wrong, grounded correct → always grounded):
      per-surface persistent chats (home/deck/puzzle), streaming markdown, UIKit-backed
      selection, per-message copy; (e) home = 2-column card grid with tinted SF Symbol deck
      tiles (`pack.json` icon/accent), puzzle rows carry interaction-type glyphs; (f) two stale
      api test assertions refreshed. - [x] 34. SUBMITTED TO APP REVIEW (2026-08-05, API-verified WAITING_FOR_REVIEW at 11:31 UTC).
      Version 0.1 build 2, free, all 175 territories, manual release. Listing: Education +
      Developer Tools, 4+ age rating (full questionnaire), privacy label "Data Not Collected"
      + published policy (unclecode.github.io/rustchap/privacy.html), DSA non-trader active,
      content rights declared, five 6.9" screenshots, reviewer notes explain the offline
      verdict design and the BYO-key tutor. Submission id 8d58ae23; the user pressed the
      final Submit personally. Remaining after approval: user presses Release, then add the
      App Store link to README + Pages. NOTE: ASC Developer-role API key can read review
      submissions but not submit (403) - a future App Manager key would fully automate.
- [x] 33. PUBLIC + LICENSED (2026-08-05): repo public at github.com/unclecode/rustchap,
      Apache-2.0 WITH Commons Clause (use/modify/contribute freely; selling not granted —
      user's choice over MIT/Apache dual). Public README, GitHub Pages from /docs:
      privacy policy + support at unclecode.github.io/rustchap. History secret-scanned
      clean before the flip. External testers skipped by user decision — feedback comes
      from the store. Store prep DONE: 5 screenshots 1320×2868 (.context/store-screenshots,
      gitignored), listing draft (.context/store-listing.md), trademark check clean
      (name OK with independence disclaimer; Ferris is CC0).
- [x] 28. DECIDED (2026-08-05): **v0.1 ships serverless.** The app is fully functional
      offline: bundled content, precomputed verdicts on device, progress in SwiftData, tutor
      on-device by default (OpenRouter only when the user supplies a key). `services/api`
      stays in the repo and in CI, but nothing is deployed and no ops burden exists.
      Deliberately given up: cross-device sync, server-pushed content, live compilation,
      server-side telemetry. REVISIT TRIGGERS (deploy only when one becomes real): users ask
      for sync; content cadence outgrows app releases; a puzzle type needs live compilation;
      aggregate tester telemetry becomes worth having. First deployment shape unchanged: one
      container + managed Postgres; step 13's Docker sandbox gets built then. Side effect:
      serverless keeps the privacy story near "Data Not Collected" and avoids the
      account-deletion requirement.
- [x] 31. Internal TestFlight SHIPPED (2026-08-05): ASC app record "RustChap" (id 6798180343,
      SKU rustchap-001, bundle dev.rustchap.RustChap auto-registered by the distribution
      export), Release archive + Apple Distribution signing + upload ALL headless via the
      Mac's Xcode account (`xcodebuild -exportArchive` destination=upload), export-compliance
      key in Support/Info.plist. Build 0.1(1) Ready to Submit; internal group "Core Testers"
      with automatic distribution; account holder invited. ASC API key for CI uploads located
      (touchup-notary, SK8BLGJ8R8, Developer role) and installed at
      ~/.appstoreconnect/private_keys. External testers (the ~6 friends) still pending:
      external group + first-build beta review.
- [x] 29. CI/CD SHIPPED (2026-08-05, `.github/workflows/ci.yml`): every push/PR runs
      rust-and-content on ubuntu (workspace tests; linter --check recompiling all
      enumerated submissions on pinned 1.97.1 — verdict drift fails the build; audit) +
      ios-build on macos (simulator-SDK compile, newest runner Xcode, no signing).
      First run green: 2m16s / 1m06s. TestFlight upload deliberately deferred to 31.

## Post-launch (v0.2 direction, user-set 2026-08-05)
- [x] Levels layer SHIPPED (2026-08-05): Foundations/Core/Advanced/Mastery tiers above
      decks; chips selector on home; per-level sequential unlock, levels free to enter;
      existing 15 decks tagged 8 core + 7 advanced. Structure only — content next.
- [x] Foundations content SHIPPED (2026-08-05): 5 decks, 24 nodes (5 lectures + 19
      puzzles), 168 verified submissions — First Steps, Types & Functions, Structs &
      Enums, Collections, Strings. All adapted from rustlings (MIT, attributed per node);
      10 new concepts in the skill library. E-currency only at this tier; guessability
      11-15%; one allowlisted tie (strings-basics.002, deref-coercion lesson). Curriculum
      now 20 decks / 105 nodes / 532 verified submissions.
- [ ] Mastery content: atomics/ordering, advanced lifetimes, macros, FFI — ongoing rhythm.

### Original step list
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
