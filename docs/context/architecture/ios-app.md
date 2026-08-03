---
title: iOS app
status: living
sources:
  - apps/ios/RustChap.xcodeproj/project.pbxproj
  - apps/ios/RustChap/RustChapApp.swift
  - apps/ios/RustChap/Core/Models.swift
  - apps/ios/RustChap/Core/ContentStore.swift
  - apps/ios/RustChap/Core/LocalEvaluator.swift
  - apps/ios/RustChap/Features/DeckListView.swift
  - apps/ios/RustChap/Features/TrackListView.swift
  - apps/ios/RustChap/Core/Progression.swift
  - apps/ios/RustChap/Features/PuzzleScreen.swift
  - apps/ios/RustChap/Features/ResultView.swift
  - apps/ios/RustChap/PuzzleUI/RustLexer.swift
  - apps/ios/RustChap/PuzzleUI/CodeSurface.swift
  - apps/ios/RustChap/Features/ConceptView.swift
  - apps/ios/RustChap/Core/APIClient.swift
  - apps/ios/RustChap/Core/ProgressStore.swift
  - apps/ios/RustChap/Core/Keychain.swift
  - apps/ios/RustChap/Core/SyncService.swift
  - apps/ios/RustChap/Features/ProfileView.swift
  - apps/ios/Support/Info.plist
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
- **Content** (`ContentStore.swift`): `@MainActor @Observable`; bundled loading reads
  `packs/index.json` for curriculum order (**never hardcode the deck list** — a hardcoded
  five-track array once hid ten decks whenever the server was down); missing pack dirs are
  skipped. `nextPuzzleId(after:)` is deck-scoped.
- **Screens** (`Features/`): `TrackListView` (sections per pack), `PuzzleScreen` (goal, monospaced
  code preview with slot substitution, placeholder controls — choice `Menu`s, drag-to-reorder
  blocks, candidate rows — Run button), `ResultView` (status icon, rank label, metrics vs best,
  categorized diagnostics, explanation on solve, Retry/Next).

Verified by simulator-SDK build plus a macOS harness that compiles the real
`Models.swift`/`LocalEvaluator.swift` and checks hashes against the linter-generated outcomes.

## Shipped: the semantic code surface (steps 9–10, `PuzzleUI/`)

- **`RustLexer`**: display-side tokenizer (keywords, types, strings, numbers, macros, comments,
  lifetimes) — colors tokens, never decides meaning. `CodeLineBuilder.lines(template:slots:)`
  splits a template on ⟦markers⟧ into renderable lines of `LineElement.token/.slot`.
- **`CodeSurface`**: horizontal-scroll (never wraps) token lines; slots render as inline
  **`SlotChip`s** — filled (tinted, current value) or empty (dashed placeholder, slot label);
  after a failed run, chips named in diagnostic `slot_ids` turn red. Tap → **`ChoiceTray`**
  bottom sheet listing choices as highlighted code. `CodeText` renders static highlighted code
  (block rows, candidate cards, prefix/suffix).
- **Result presentation** (`ResultView`): `RankLadder` (Solved → Fluent → Optimal with achieved
  steps filled + "X needs: …" for the next rank), and a whole-solution score comparison —
  "You: 1 clone · 1 edit" vs "Best known: 0 clones · 2 edits" via `ResultView.phrase` (never
  per-metric "best" columns: thresholds are conditions, not a rival solution). Result sheet
  opens at `.large`; `sensoryFeedback` success/error on evaluation.
- **SwiftUI lessons (RCA)**: `.sheet(isPresented:)` + `if let` renders an empty sheet when the
  state isn't visible to the content closure — always `.sheet(item:)`. NavigationStack drops
  path mutations made during sheet dismissal — navigate in the sheet's `onDismiss`
  (`pendingNextId` in `PuzzleScreen`).
- **Automation**: `--open <puzzle-id>` launch argument deep-links to a puzzle
  (`RustChapApp.init`), used for simulator screenshot verification.
- **Skills** (`ConceptView.swift`): `content/concepts` is bundled as a second folder reference;
  `ContentStore.concepts(for:)` maps a puzzle's `concepts` ids to loaded `Concept`s. The puzzle
  screen shows a "Skills for this puzzle" section (title + summary rows); tapping opens the
  lecture sheet with highlighted example code — teaches what the puzzle needs, Euclidea-style.

## Shipped: server integration (step 15 — Milestone 2)

- **`APIClient.swift`**: URLSession client for `services/api`, 3s timeout; default base
  `http://localhost:8787` (simulator shares the Mac's loopback; loopback is ATS-exempt, and
  `Support/Info.plist` adds `NSAllowsLocalNetworking` for LAN-IP device testing). Override with
  the `--api <url>` launch argument. `SubmissionBody`/`PuzzleOperation: Encodable` mirror the
  Rust `Submission` wire shape.
- **Server-first content**: `ContentStore.refreshFromServer()` (called from `RustChapApp.task`)
  replaces bundled packs with the server's copy when reachable — new content without an app
  rebuild; silent fallback to bundled offline. `ContentSource` drives a track-list footer badge.
  Server-fetched puzzles keep the bundled outcomes sidecar only when id+version match.
- **Server-first evaluation**: `ContentStore.evaluate` POSTs to `/evaluate`, falling back to the
  on-device `LocalEvaluator` lookup offline. `EvaluatedVia` (server-precomputed / server-compiled
  / on-device) is shown as a small label on the result sheet — the wiring is visible, which is
  how the alphabetical-pack-order bug was caught (fixed server-side via `content/packs/index.json`).
- **Automation**: `--autorun` submits on appear; `--choose slot=choice,slot=choice` pre-applies
  selections — together with `--open` they let simulator scripts solve puzzles headlessly
  (used to verify persistence without tapping).

## Shipped: durable local progress (step 18 — SwiftData)

- **`ProgressStore.swift`**: `PuzzleProgressRecord` (@Model, unique per `puzzleId`) — solved flag,
  best rank + best metrics JSON, attempt count, first/best solved timestamps.
  `ProgressRecorder.record` folds each evaluation in with the plan's merge rules: solved beats
  unsolved, better rank beats worse, a new attempt never downgrades the stored best. A changed
  `puzzleVersion` resets bests but keeps attempt history.
- Container attached in `RustChapApp` (`.modelContainer(for: PuzzleProgressRecord.self)`);
  `PuzzleScreen.run` records after every evaluation; `TrackListView` shows per-puzzle badges via
  `@Query` (⭐ optimal / teal ✓ fluent / green ✓ solved / dashed circle attempted-unsolved).
- Verified headlessly: automation solved two puzzles at different ranks, app killed and
  cold-relaunched — badges restored from the store.

## Shipped: anonymous identity + cloud sync (step 19 client — Milestone 3)

- **`Keychain.swift`**: minimal SecItem wrapper + `DeviceCredentials` (device_id, token). The
  Keychain outlives the app container — verified: full `simctl uninstall` + reinstall recovered
  the identity and pulled all progress back from the server with an empty push.
- **`SyncService.swift`** (@Observable, owns the shared ModelContainer's mainContext):
  `bootstrap()` at launch = ensure registered → `syncNow()`; another `syncNow()` after every
  recorded attempt. The server's merge is the authority — local records are pushed, the merged
  response overwrites local state (attempt_count max-guarded for in-flight attempts).
  **401 self-heals**: token rejected → credentials dropped → fresh registration → one retry
  (covers server-side wipes/revocation; found by deleting the device row mid-test).
  Debug trail written to `Documents/sync.log`.
- **`APIClient`**: register/profile/sync endpoints; every request attaches
  `Authorization: Bearer` from `DeviceCredentials` when present — authenticated evaluates get
  attempt-logged server-side for free. `JSONDecoder.api`/`JSONEncoder.api` handle chrono's
  fractional-seconds RFC3339 (plain `.iso8601` cannot parse microseconds).
- **`ProfileView.swift`**: optional name/email form (never required to play), device identity +
  sync state display; person icon in the track-list toolbar.
- **RCA — Keychain needs a signed binary**: `CODE_SIGNING_ALLOWED=NO` simulator builds make
  `SecItemAdd` fail silently (writes no-op, reads nil). Build simulator binaries with default
  ad-hoc signing ("Sign to Run Locally"); never pass CODE_SIGNING_ALLOWED=NO.

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

## Navigation (two levels — the deck model, shipped)

`Route` enum (`.deck(id)` / `.puzzle(id)`) drives one NavigationStack. **`DeckListView`** is home:
every deck by name with progress (`solved/total`, ★ optimal count), locked decks visible
(lock icon), planned empty decks marked "Soon". Unlock = previous deck fully solved, derived
client-side (shared `Progression` helpers; empty decks never complete). **Locked decks are
browsable**: tapping opens `DeckDetailView` (TrackListView.swift) with the puzzle list grayed +
per-row locks + "Solve the previous deck to unlock" — preview what's ahead, play nothing.
`--open` also accepts a deck id (no dot → deck route). `ContentStore.nextPuzzleId(after:)` is
deck-scoped; the last solve in a deck offers "Deck finished — back to the decks"
(`onDeckComplete` → path = []), landing where the next chest just unlocked. Deep link
`--open <puzzle>` builds the two-element path (deck id = puzzle id prefix). No third level,
no dashboards — by decision.

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
