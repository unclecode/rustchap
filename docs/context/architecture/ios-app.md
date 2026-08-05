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
  - apps/ios/RustChap/Core/TutorService.swift
  - apps/ios/RustChap/Core/TutorProbe.swift
  - apps/ios/RustChap/Features/TutorSheet.swift
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
  truth). Build: Swift 6, iOS 17 target, `GENERATE_INFOPLIST_FILE`. **App icon** (2026-08-05):
  `Assets.xcassets/AppIcon.appiconset` — Ferris at 1024px in the three modern variants
  (light: warm gradient, opaque; dark: transparent glyph; tinted: grayscale glyph), wired via
  `ASSETCATALOG_COMPILER_APPICON_NAME`; dark/tinted activate via the user's home-screen icon
  style, not the system appearance alone.
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
- **RCA — ghost selections across "Next puzzle" (found on-device 2026-08-04)**: replacing the
  path wholesale (`path = [.deck, .puzzle(next)]`) keeps the depth-2 destination's **view
  identity** — `@State selections` survives and `.onAppear` never re-fires, so the old puzzle's
  choices rode into the next puzzle's submission (5 ops against a 3-slot table → offline lookup
  miss → bogus "Invalid submission · offline"). Two-layer fix: `.id(puzzleId)` on `PuzzleScreen`
  in `RustChapApp`'s `navigationDestination` (fresh identity per puzzle), and `PuzzleScreen.run`
  builds operations **from the puzzle's own slots**, never by dumping the selections dictionary.
  Only surfaced via the hand-tap journey solve → "Next puzzle" → play — deep-link automation
  can't reproduce it; that class of flow needs real navigation.
- **Automation**: `--open <puzzle-id>` launch argument deep-links to a puzzle
  (`RustChapApp.init`), used for simulator screenshot verification.
- **Lesson nodes (2026-08-04)**: `Interaction.lesson(sections:)` renders a reading layout in
  `PuzzleScreen.interactionSection` — prose paragraphs + `CodeText` cards with captions — and
  the bottom bar swaps Run for **"Got it"** (`completeLesson()`: records a synthetic
  solved/rank-solved `EvalResult` via `ProgressRecorder`, then path-replaces to the next deck
  node). `run()`/`canRun` guard the lesson case; deck rows show an indigo book icon
  (`TrackListView.puzzleRow`); `Puzzle.scoring` is optional (lessons have none — `ResultView`
  falls back to an empty `Scoring`, unreachable in practice). Progression counts lessons like
  puzzles: reading gates deck completion.
- **On-device AI tutor (2026-08-04, experimental)**: `Core/TutorService.swift` +
  `Features/TutorSheet.swift` + `Core/TutorProbe.swift` (the `--fm-probe` spike harness).
  Foundation Models (iOS 26, Apple Intelligence) behind `TutorAvailability` — the sparkles
  toolbar button (`.tutorButton { context }` modifier on home/deck/puzzle/result screens)
  **does not exist** when the model is unavailable. Spike finding that shapes the design: the
  raw 3B model invents Rust rules ("&str is a generic type"); grounded in bundled material it
  answers correctly at ~1.4–3s. So `TutorContext` pins every session to app-owned content —
  global = concept-library summaries; puzzle = full lectures for the puzzle's concepts +
  template + player picks + real diagnostics + explanation — with a never-invent,
  say-not-sure leash (`TutorContext.instructions`). Chat UI: suggested-question chips,
  multi-turn `LanguageModelSession`, **streamed** answers (cumulative snapshots via
  `streamResponse`; the bubble is created on first token and rewritten — the
  unterminated-fence fallback in `TutorMarkdown` makes half-streamed code blocks render
  highlighted), markdown rendering (`TutorMarkdown`: headings/lists/inline via
  AttributedString, fenced blocks through `CodeText`/RustLexer; `--md-preview` shows it on
  the FM-less simulator). **One durable conversation per surface** (clarified by the
  user 2026-08-04: scope IS the thread — no history browser): `TutorConversationRecord`
  (SwiftData, JSON transcript) keyed by `subjectId` = `home` / `deck:<id>` /
  `puzzle:<id>`; each surface's tutor resumes its own thread, saved after every exchange,
  LRU-pruned past 30 threads; a fresh session folds the last 6 turns of that thread into
  its instructions so relaunch keeps context. Deck surfaces get a deck-scoped grounding
  packet (`TutorContext.deck`: deck arc + concept summaries).
  New-chat toolbar button clears it; per-message copy buttons put raw markdown on the
  pasteboard; `.textSelection(.enabled)` on both bubble kinds;
  `.scrollDismissesKeyboard(.interactively)` + tap-to-unfocus. All FM code is
  `#available(iOS 26)`-gated; app min target stays iOS 17.
- **The cost language (2026-08-05, user-approved design)**: one letter per metric
  (`CostLanguage.all`: E edits, C clones, W warnings, M mut, L loops, U unsafe) and one
  notation ("0C·2E") across goal chip, live meter, result sheet, and deck-card currency
  badges. `Core/CostLanguage.swift` mirrors `metrics.rs` counting EXACTLY (substring clone
  calls; word-boundary for/while/loop, mut, unsafe) — live numbers are a preview from current
  picks; outcomes at Run stay truth. `PuzzleScreen`: gold `★ 0C·2E` chip on the goal card,
  cost pill left of Run (gray while picking → per-letter red over budget → all-green +
  hairline ring + one soft haptic at goal; W renders dimmed "W?" until Run).
  `CostLegendSheet` (tap chip or meter): half-height sheet — approved exception to the
  all-large drawer rule — active letters tagged "this puzzle", others dimmed. Design mock:
  claude.ai artifact 57028cca.
- **Tutor engines (2026-08-05)**: `Core/TutorEngine.swift` — a `TutorEngine` protocol with two
  implementations behind `TutorEngineFactory`: `LocalTutorEngine` (Foundation Models, gated)
  and `OpenRouterTutorEngine` (SSE streaming chat completions; pinned model in
  `TutorSettings.openRouterModel` = deepseek/deepseek-v4-flash-0731, $0.09/$0.18 per M —
  cheapest capable per the 2026-08 pricing pass; `reasoning` deltas ignored). Selection in
  ProfileView ("AI tutor" section: engine picker + SecureField); key in the Keychain
  (`openrouter_api_key`) — typed by the user in Profile, the ONLY entry path (the dev
  launch-arg injection was removed 2026-08-05 by user decision: keys are never provisioned
  outside the settings UI).
  Cloud errors fall back to the local engine for that question and stay local; a failed
  question is removed from the cloud history so the transcript never holds unanswered turns.
  `TutorAvailability` = cloud configured OR FM available (the sparkles button now appears on
  FM-less devices when cloud is set). Both engines stream cumulative snapshots via
  `AsyncThrowingStream.makeStream` (@MainActor — the Swift 6 sending-closure fix).
- **Scoreboard (2026-08-05)**: `Features/ScoreboardSheet.swift` — chart toolbar button on
  home/deck screens (`.scoreboardButton()`, same always-there pattern as the tutor; the
  profile keeps identity/settings, the scoreboard owns progress). Large drawer: three stat
  tiles (solved/total, ★ optimal, attempts) + per-deck rows with icon tile, accent progress
  bar, counts. `--scoreboard` launch arg opens it for screenshots.
- **Skills** (`ConceptView.swift`): `content/concepts` is bundled as a second folder reference;
  `ContentStore.concepts(for:)` maps a puzzle's `concepts` ids to loaded `Concept`s.
  `SkillsSheet` (book toolbar icon) lists them and pushes `ConceptLectureView`; `HintsSheet`
  (lightbulb icon) shows hints — both moved OUT of the puzzle scroll so the screen stays compact.
- **No-scroll puzzle layout**: Run is pinned via `safeAreaInset(edge: .bottom)` in a material
  bar — always visible; skills/hints live in the toolbar. The scroll contains only goal + code.
- **Appearance**: `@AppStorage("appearance")` (system/light/dark) → `.preferredColorScheme`;
  segmented picker in ProfileView.
- **Offline-safe profile**: `SyncService.updateProfile` always writes the local cache
  (UserDefaults) and marks dirty on server failure; `bootstrap()` pushes dirty profiles when
  the server returns. ProfileView renders the local cache instantly and says plainly when a
  save is device-only.
- **Progress dashboard** (ProfileView, phase 7): solved/optimal/attempt stat blocks +
  strongest / needs-more-work concept lists with progress bars, computed on-device
  (`conceptStrengths`: SwiftData records joined to puzzle `concepts`; needs-work excludes
  strongest to avoid overlap). Deck home shows a "Continue" chip on the first
  unlocked-incomplete deck (`DeckListView.currentDeckId`); completing a deck's last unsolved
  puzzle shows "Deck complete — the next chest is open" (`PresentedResult.deckCompleted`).
  `--profile` launch arg opens the sheet for screenshot automation.

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
since 2026-08-04 a **two-column card grid** (LazyVGrid), each deck card carrying a tinted
SF Symbol tile (`pack.json`'s display-only `icon` + `accent` fields; `accentColor(_:)` maps
named colors, unknown → app tint), progress line (`solved/total`, ★ count), the current deck
ringed in its accent with a Continue chip, locked decks dimmed with lock badges, planned
empty decks marked "Soon". Unlock = previous deck fully solved, derived
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
