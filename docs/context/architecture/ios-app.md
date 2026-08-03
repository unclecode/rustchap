---
title: iOS app
status: backlog
sources: []
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

> **Agreed design, no code yet.** Lives in `apps/ios/`. When implementation lands, add the real
> file paths to `sources:` and flip `status` to `shipped`.

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

## The semantic code surface

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
