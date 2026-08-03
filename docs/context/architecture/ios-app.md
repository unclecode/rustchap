---
title: iOS app
status: living
sources:
  - apps/ios/RustChap.xcodeproj/project.pbxproj
  - apps/ios/RustChap/RustChapApp.swift
  - apps/ios/RustChap/Core/Models.swift
  - apps/ios/RustChap/Core/ContentStore.swift
  - apps/ios/RustChap/Core/LocalEvaluator.swift
  - apps/ios/RustChap/Features/TrackListView.swift
  - apps/ios/RustChap/Features/PuzzleScreen.swift
  - apps/ios/RustChap/Features/ResultView.swift
related:
  - foundation/interaction-types.md
  - architecture/backend.md
  - roadmap/build-order.md
---

# iOS app

Native iPhone client — SwiftUI, no cross-platform framework. The tactile interaction (token
manipulation, gestures, haptics, instant transitions) *is* the product's competitive advantage;
cross-platform UI would compromise the product actually used today to save hypothetical Android
work. Android later gets its own first-class Compose client consuming the same contracts.

## Shipped: the step-8 shell (`apps/ios/`)

Launch → track list → puzzle → result → retry/next, fully offline against bundled content.

- **Project**: hand-authored `project.pbxproj` (objectVersion 77, `PBXFileSystemSynchronizedRootGroup`
  over `RustChap/` — no xcodegen dependency). `content/packs/` is added as a **folder reference**
  resource, so the app bundles the repo's packs directly (hierarchy preserved; single source of
  truth). Build: Swift 6, iOS 17 target, `GENERATE_INFOPLIST_FILE`.
- **Models** (`Models.swift`): explicit-CodingKeys mirrors of the puzzle contract — `Puzzle`,
  `Interaction` (tagged enum), `Outcomes`, `EvalResult`, `Diagnostic`. Deliberately no
  `convertFromSnakeCase` (it would mangle dictionary keys like metric names).
- **Evaluation** (`LocalEvaluator.swift`): `PuzzleOperation` + `OpsHash.canonicalJSON` /
  `OpsHash.hash` — byte-exact mirror of Rust `puzzle-schema::ops` (select ops sorted by slot_id,
  compact JSON, SHA-256). `LocalEvaluator.evaluate` looks the hash up in the bundled outcomes:
  Milestone-1 offline evaluation is exact, not mocked. **Any change here or in Rust `ops.rs` must
  keep the two byte-identical** (named `PuzzleOperation` to avoid shadowing Foundation.Operation).
- **Content** (`ContentStore.swift`): `@MainActor @Observable`; loads `packs/` from the bundle in
  fixed curriculum order; `nextPuzzleId(after:)` drives Next.
- **Screens** (`Features/`): `TrackListView` (sections per pack), `PuzzleScreen` (goal, monospaced
  code preview with slot substitution, placeholder controls — choice `Menu`s, drag-to-reorder
  blocks, candidate rows — Run button), `ResultView` (status icon, rank label, metrics vs best,
  categorized diagnostics, explanation on solve, Retry/Next).

Placeholder interaction controls are scaffolding: steps 9–10 replace the preview + controls with
the semantic code surface below. Verified by simulator-SDK build plus a macOS harness that
compiles the real `Models.swift`/`LocalEvaluator.swift` and checks hashes against the
linter-generated outcomes.

## Stack

- **Swift 6 + SwiftUI**; Observation (`@Observable`), `async/await`, `URLSession`, Swift Testing,
  SwiftPM. Minimal UIKit bridging only where SwiftUI is genuinely insufficient.
- **SwiftData** for local persistence: downloaded puzzle packs, progress, submitted solutions,
  personal bests, pending submissions, cached explanations. Canonical puzzles stay versioned JSON —
  SwiftData caches decoded models and user state, it is never the authoring format
  (`Puzzle JSON → Codable models → SwiftData cache`).
- No third-party state-management framework; Observation is sufficient.
- Anonymous local installation ID first; Sign in with Apple when cloud progress arrives
  (see [backend](backend.md) for the token flow).

## The semantic code surface (next: steps 9–10)

The hardest and most important UI component. **Not a text editor** — a structured puzzle tree
rendered as native tokens that merely looks like code:

```text
CodeSurface
├── StaticToken
├── SelectableSlot / EditableSlot
├── DraggableBlock
├── ErrorMarker / ErrorUnderline
├── ChangedToken
└── OwnershipOverlay (later)
```

Priorities: readable monospace typography, accurate wrapping on small screens, large invisible tap
targets, smooth token replacement, native haptics, undo, reset, and a clear visual distinction
between static and editable code.

## Architecture

Feature-oriented, no VIPER/Clean-Architecture theatre, no Redux framework:

```text
App/
  Core/        API/  Persistence/  Models/  DesignSystem/
  Features/    Puzzle/  PuzzlePath/  Results/  Progress/  Settings/
  PuzzleUI/    CodeSurface/  TokenTray/  DragBlocks/  CompilerDiagnostics/
```

Within each feature: `PuzzleScreen` / `PuzzleViewModel` / `PuzzleState` / `PuzzleService`.

## Navigation

Euclidea-shaped: `Track map → Puzzle → Result → Next`. Secondary screens only: profile, progress,
settings, puzzle explanation, account management. No course dashboard. Profile shows current track,
puzzles solved, optimal solutions, attempts, strongest/weakest concepts — no XP, coins, or badges.

## Offline and sync behaviour

The app never requires network merely to open. Attempts save locally immediately, evaluate when
online, and merge with these rules: solved beats unsolved; better score beats worse; server-verified
beats local-only; newest attempt does not automatically beat best attempt. Identity edge cases
(reinstall, new phone, sign-out/in, token expiry, Apple credential revocation, puzzle version
changes) are handled from the beginning.

## Local responsiveness

Before any network call the client validates instantly: required slots filled, legal token
combinations, syntax-shape constraints, known-impossible states. On Run: haptic → tokens lock →
code pulses → result arrives (optimistic animation). A shared Rust core via UniFFI (schema
validation, normalisation, local scoring) is a possible later extraction — explicitly not v1.
