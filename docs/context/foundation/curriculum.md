---
title: Curriculum
status: living
sources:
  - content/packs/index.json
related:
  - foundation/product-vision.md
  - roadmap/v0.1-scope.md
  - architecture/puzzle-format.md
---

# Curriculum

The curriculum is organised around **points of friction unique to Rust**, not around beginner
course syllabi. The target user is an experienced programmer; syntax appears incidentally.

## The 16 friction areas (full arc)

1. Moves, copies, and partial moves
2. Borrowing and reborrowing
3. Lifetimes and elision
4. Slices and zero-copy APIs
5. `Option`, `Result`, and `?`
6. Pattern matching and destructuring
7. Iterators and ownership variants
8. Traits, bounds, and associated types
9. Generics versus `impl Trait` versus `dyn Trait`
10. Smart pointers: `Box`, `Rc`, `Arc`, `RefCell`, `Mutex`
11. Closures and `Fn`, `FnMut`, `FnOnce`
12. Interior mutability
13. Async ownership, `Send`, and `'static`
14. Pinning and advanced async
15. Unsafe Rust and sound abstractions
16. API design and idiomatic refactoring

## The deck model (decided 2026-08-03 — Euclidea structure)

Two levels, never more: **decks → puzzles**. The home screen lists every deck by its real
curriculum name — locked decks stay visible ("you can see the road ahead"). A deck holds as many
puzzles as the bank provides (no fixed 8). Solving **all** puzzles in a deck (any rank) unlocks
the next; an empty (planned) deck never completes, so the chain stops there. Unlock state is
derived client-side from `packs/index.json` order + progress — no schema field.

**The journey (15 decks, `content/packs/index.json` — reordered 2026-08-03 as a pedagogical
ramp, each deck standing on the previous):**

1. Move or Borrow → 2. Remove the Clone → 3. Slices & Views (views motivate lifetimes) →
4. Repair the Lifetime → 5. Option & Result (breather; everyday types) → 6. Pattern Matching
(pairs with Option) → 7. Build the Iterator → 8. Closures (deepens what iterators use) →
9. Traits & Bounds → 10. Generics vs dyn (builds on traits) → 11. Smart Pointers →
12. Interior Mutability (planned) → 13. Design the API (capstone — synthesizes everything) →
14. Async & Send (planned) → 15. Unsafe Rust (planned).

Planned decks are pack dirs with `order: []` (shown "Soon"). Deck order is re-arrangeable in
index.json as decks fill; two-optimal ties are allowed when both answers are genuinely idiomatic
(the explanation says so explicitly — e.g. named-variant vs wildcard, match vs if let).

Content scale comes from the **ingestion pipeline** (phase 6): mine open-source banks
(Rustlings, Exercism, compiler/Clippy tests…), transform + annotate each exercise into the
puzzle schema, lint, and assign to a deck — not from hand-authoring fixed sets.

## Seed puzzles (shipped — one per track, `content/packs/<track>/`)

The first five hand-authored puzzles deliberately exercise the whole engine; each pack currently
holds one puzzle plus its linter-generated `outcomes/` sidecar:

| Puzzle | Interaction | Engine feature it proves |
|---|---|---|
| `move-or-borrow.001` "Use It Twice" | minimal-edit | compile failures (E0382) + full Solved/Fluent/Optimal gradient |
| `remove-the-clone.001` "Borrow the Tags" | minimal-edit | Clippy-based rank (`clippy::ptr_arg` splits `&Vec<String>` from `&[String]`) |
| `repair-the-lifetime.001` "The Longest One" | slot-selection | 26/27 combinations fail with categorized lifetime errors; repeated-slot templates |
| `build-the-iterator.001` "Evens, Doubled" | block-arrangement | runtime tests discriminate: map-before-filter compiles but fails the test |
| `design-the-api.001` "First Word, Zero Copies" | best-solution | all candidates compile; only metrics (clone_count 2/1/0) rank them |

Authoring lesson recorded: `clippy::ptr_arg` fires only when the body provably works with the
slice type (a real str/slice method call) — usage solely through `println!` suppresses it.

## Concept library (shipped — `content/concepts/`)

Thirteen tap-to-learn skills backing the puzzles' `concepts` references (linter-enforced):
`move`, `borrow`, `deref-coercion`, `clone`, `slice`, `lifetime`, `elision`, `iterator`,
`zero-copy`, `api-design`, `copy`, `mutability`, `borrow-scope`. Each is a one-line summary +
2–4 lecture paragraphs + a highlighted example, written for an experienced programmer — the
minimum needed to attempt the puzzle, never a course. New puzzles should reference existing
concepts where possible; add a new concept file only when a genuinely new instinct appears.

## Ingestion pipeline (running — `tools/fetch-sources.sh` + `tools/catalog-sources.py`)

`fetch-sources.sh` shallow-clones the source banks into gitignored `bank/sources/` (rustlings:
94 exercises, exercism/rust: 106); `catalog-sources.py` emits `bank/catalog.json` mapping each
candidate to a suggested deck (64 mapped at first run). Transformation is per the standing rule:
extract the insight, redesign for constrained phone interaction, attribute (`source.origin` +
licence), and the linter compiles every combination (`--summary` shows each puzzle's outcome
distribution for review).

**Batch 1 (2026-08-03):** Move or Borrow filled to 6 puzzles from rustlings move_semantics
material — Copy or Move? (clone_on_copy discrimination) · Give It Away (when moving IS right) ·
Borrow, Then Move (NLL ordering) · One Writer at a Time (all 6 orders compile, only one passes
the tests) · The Loop That Steals (for-loop into_iter).

**Batch 2 (2026-08-03):** Remove the Clone filled to 6 — The Printing Clone (&x.clone()
clone-then-borrow smell) · Clone in a Loop (per-iteration waste; unclOned move dies on the 2nd
iteration) · Struct Field Peek (field borrow vs partial move) · Sort Without Copy (sort() vs
sort_by_key clone; length-key compiles but fails the test) · Cheap to Copy (derive(Copy) deletes
every clone). Deck order interleaves difficulty (003 before 002).

**Batch 3 (2026-08-03) — the mass fill:** Repair the Lifetime → 6 (First of Two, Struct Holder,
Dangling Local E0515, The Static Promise, Two Sources = rustlings lifetimes2 direct) ·
Build the Iterator → 6 (Sum of Squares, Reuse After the Loop iter-vs-into_iter, Find the First
Long One, Collect the Names Vec<&str>, Fold the Total loop→fold→sum ladder) · Design the API → 3
(Take What You Need, Mutate or Return mut-count ladder) · **Slices & Views born** (The Nice
Slice = primitive_types4 direct, Trim Without Buying) · **Option & Result born** (Maybe the
First, The ? Shortcut = errors2 direct — unwrap panics, unwrap_or swallows, both caught by
tests). Totals: 31 puzzles, 249 verified submissions, 16 concepts, 7 live decks + 5 Soon.
`clone_count` extended to all explicit copies (.to_vec/.cloned) during this batch.

**Lecture nodes (2026-08-04) — reading joins the curriculum:** `interaction.type: "lesson"`
puzzles interleave freely with playable ones in `pack.order` (see
[interaction-types](interaction-types.md)). The user's structural rule: **every deck opens
with a lecture** (first-contact teaching), plus mid-deck lectures where a second topic
cluster starts. Full pass shipped same day: 15 openers + 4 mid-deck (`'static` in Repair the
Lifetime, `?`/error-propagation in Option & Result, iter/into_iter in Build the Iterator,
Send in Async & Send) + the original "Own, Lend, or Give" (stays mid-deck after Give It
Away). Audit ramps show lessons as `L` (e.g. `L112L232`).
Totals: **81 curriculum nodes = 61 puzzles (364 verified submissions) + 20 lectures.**
### Writing style (standing rule, tightened 2026-08-07 after a user complaint)

Plain international English, Rust domain only, industry-standard names, inline code for every
type/keyword in prose (lesson prose renders inline markdown), no em dashes. The 2026-08-07
review found this rule was too vague to hold: a scan of 636 prose sentences found 50
semicolon-welded clauses, 112 rhetorical colons, and 13 sentences over 32 words. The user's
example was `A method that only reads takes &self; a method that consumes its value takes
self.` — reference-manual register, not explanation.

**The model is now google/comprehensive-rust** (CC-BY-4.0), which is written for the same
audience (engineers fluent in another language). Its rules, adopted verbatim:

1. **Anchor to the language the reader already knows in the first sentence.** "You use `if`
   expressions exactly like `if` statements in other languages." "You will recognise the shape
   from `switch` in C, Java, or JavaScript, but three things are different."
2. **Short declarative sentences, one idea each.** No semicolons joining clauses. No colons
   doing rhetorical work (colons introduce lists only).
3. **No invented metaphors.** "A struct names a shape" was meaningless; say "a struct groups
   several values under one name."
4. **Say plainly what is NOT covered yet**, and name where it is covered. This is what prevents
   the silent jumps (the user hit one when `match` appeared inside the enum lecture with no
   prose introducing it).
5. **Prose is short; the code carries the weight.** Their student-facing text is often ~40 words
   plus a snippet; the depth lives in instructor notes. Our equivalent: depth lives in the
   puzzles.
6. **One lecture teaches one thing.** The failure case was `Shape Your Data`: struct + impl +
   `&self`/`self` + enum + `match` + exhaustiveness in 159 words.

Enforcement is planned as `tools/check-style.py` in CI (semicolons, rhetorical colons, sentence
and lecture length, em dashes, missing attribution) — style must not depend on the author's
memory, which is exactly how the regression happened.

**Batch 6 (2026-08-04) — the journey completes; Phase 6 done:** Async & Send born (Await It —
a 15-line std-only `block_on` embedded in the template makes async compile-verifiable; Move It
to the Thread = rustlings threads1 E0373; Send Across the Await — Rc held across .await makes
the future !Send, probed by a `requires_send` fn standing in for tokio::spawn) · Unsafe Rust
born (The Unsafe Gate — optimal is ONE unsafe block, owning it; Narrow the Blast Radius — the
unsafe-fn candidate fails because the shared test won't sign its contract; No Unsafe Needed —
transmute vs to_le_bytes) · 3 concepts (async-await, send-and-static, unsafe-rust; 25 total) ·
**Step-23 audit shipped** (`tools/audit-progression.py`): guessability measured as
optimal-rate, deliberate ties allowlisted, two coin-flip puzzles widened to 3 choices.
**Final: 61 puzzles, 364 verified submissions, 15/15 decks alive.**

**Batch 5 (2026-08-03) — early decks deepened + Interior Mutability born:** Slices & Views → 5
(Split the Word — hardcoded range passes one test then lies; Chars or Bytes — UTF-8 byte/char
trap; The Tail End — window-from-the-wrong-end) · Option & Result → 5 (Default with Dignity —
unwrap_or(0) is the worse bug; Map the Maybe — indexing panics, map ferries None; Chain of
Results — the ?-chain is the only candidate that can keep its Err promise) · **Interior
Mutability born** (Count Through &self — Cell vs E0594; The Guard That Lingered — named RefCell
guard compiles then PANICS at runtime, test-caught; Shared Counter Many Hands — evaporating
get()+1 bump). Totals: **55 puzzles, 346 verified submissions, 22 concepts, 13 live decks +
2 planned** (Async & Send, Unsafe Rust).

**Batch 4 (2026-08-03) — every planned v0.1 deck alive:** Pattern Matching (Match the Shape —
swapped x,y compiles and lies; Exhaustive by Design; If Let It Be with unnecessary_unwrap) ·
Traits & Bounds (Printable — Display isn't derivable; The Weakest Bound; Default It with
derivable_impls) · Generics vs dyn (One Function Any Comparable; Box the Trait; The Unnameable
Return impl Trait) · Smart Pointers (Box the Recursion E0072 = rustlings box1; Share the Config
= rc1 with clone_on_ref_ptr; Mutate Behind Sharing Rc<RefCell>) · Closures (Capture or Take —
FnOnce trap; The Counter — move-on-Copy counts a ghost, test-caught; Fn/FnMut/FnOnce hierarchy
with mut_bindings ladder). Curriculum totals: **46 puzzles, 315 verified submissions,
21 concepts, 12 live decks + 3 planned**. Lints that verifiably fire: ptr_arg, clone_on_copy,
unnecessary_unwrap, derivable_impls, clone_on_ref_ptr; wildcard_enum_match_arm does NOT fire
via -W (pattern-matching.002 redesigned around it).

## Curriculum rebuild (planned 2026-08-07, mapped against the reference courses)

The 2026-08-07 audit compared RustChap against google/comprehensive-rust (4-day outline) and
the Rust Book TOC. Findings:

**Ordering mistakes in Foundations (mine, not inherited).** Comprehensive Rust teaches `match`
on Day 1 under *Control Flow Basics* (matching plain values, beside `if` and loops) and gives
*Pattern Matching* its own Day 2 session for destructuring structs and enums. I collapsed both
into one enum lecture. They also teach `&` references on Day 1 as a tool and the ownership
model on Day 3 — introduce, then explain.

**Real content gaps** (each taught by every reference course, absent here): loops (`for`,
`while`, `loop`, `break`/`continue`) — entirely missing; modules/paths/visibility (Rust Book
ch7); threads, channels, `Arc`, `Mutex` (every course teaches plain concurrency before async);
standard traits (`From`/`Into`, `Default`, `Display`, operators); `Drop`/RAII; testing;
error types beyond `?` (the `Error` trait, conversion); idiomatic patterns (newtype, builder,
typestate). Partial: casting/overflow, implementing `Iterator`, async depth, unsafe depth.

**Proposed six levels** (existing 112 nodes all survive; changes are splits, re-levelling, and
new decks): 1 Foundations (First Steps · Types & Functions · **Control Flow** · Structs · Enums
& Reading Them Back · Collections · Strings) · 2 Ownership (Move or Borrow · Remove the Clone ·
Slices & Views · Repair the Lifetime · **Drop & Cleanup**) · 3 Everyday Rust (Option & Result ·
Pattern Matching · Build the Iterator · **Errors That Travel** · **Modules & Visibility** ·
**Standard Traits**) · 4 Abstraction (Closures · Traits & Bounds · Generics vs dyn · Design the
API) · 5 Systems (Smart Pointers · Interior Mutability · **Threads & Channels** · Async & Send ·
Unsafe Rust) · 6 Mastery (**Idiomatic Patterns** · **Testing** · **Atomics & Ordering** ·
**FFI & Raw Pointers**). Design map: claude.ai artifact ab0c9272.

Comprehensive Rust's Android, Chromium, and Bare Metal tracks are **out of scope**:
platform-specific, unverifiable with our compile pipeline, wrong for a phone puzzle game. Its
Concurrency and Idiomatic Rust tracks are in scope.

**PILOT SHIPPED (2026-08-07): Control Flow deck** — 7 nodes (2 lectures + 5 puzzles), 45
verified submissions, adapted from Day 1 Morning: Control Flow Basics. Two lectures each
teaching one thing: *Repeating Work* (the three loop keywords, `break`/`continue`, `break`
carrying a value) and *Matching a Value* (`match` on plain values, no fall-through,
exhaustiveness, `match` as an expression, and an explicit note that destructuring enums comes
later). New concepts: `loops`, `match-basics`. This deck is the voice reference for the rebuild.

**SIX-LEVEL STRUCTURE SHIPPED (2026-08-07)**: the whole curriculum shape is now visible in the
app, with unbuilt decks showing as "Soon / In preparation" (the same placeholder pattern used
for planned decks in phase 6). 30 decks across 6 levels: Foundations 6 · Ownership 5 ·
Everyday Rust 6 · Abstraction 4 · Systems 5 · Mastery 4. Nine planned-empty decks:
drop-and-cleanup, errors-that-travel, modules-and-visibility, standard-traits,
threads-and-channels, idiomatic-patterns, testing, atomics-and-ordering, ffi-and-raw-pointers.
Two app changes were needed: `ContentStore.visibleLevels` now keeps levels whose decks are all
planned (otherwise Mastery vanished), and `Progression.isUnlocked` filters empty decks out of
the gating chain (otherwise a planned deck mid-level — threads-and-channels sits between
interior-mutability and async-and-send — would permanently block everything after it).
NOTE: the Structs/Enums split from the plan is NOT applied yet; `structs-and-enums` stays
whole until its content is rebuilt.

**CURRICULUM BUILT OUT (2026-08-08): 477 nodes across 31 decks, every deck at the
15-node bar** (18 for move-or-borrow, repair-the-lifetime, threads-and-channels,
async-and-send). Up from 119 nodes that morning. Review cards went 42 -> 528 across 64
concepts. Total model spend ~$2.

Pipeline: `tools/generate-deck.py` drafts a deck from the Comprehensive Rust extract plus
the curriculum map, converts through `tools/authoring.py`, compiles every submission with
the linter, and feeds failures back for repair rounds. `tools/repair-content.py` does the
same for already-committed content. Model comparison on 2026-08-07 (same prompt, same
deck): **gemini-3.6-flash beat gemini-3.1-pro-preview and gpt-5.6-sol** on verified-puzzle
rate at a quarter to an eighth of the cost, so Flash is the default for a measured reason.

Hard-won rules now encoded in the tooling:

- **A puzzle is broken iff it has zero solved OR not exactly one optimal.** Counting
  `solved` is wrong: `best-solution` offers three programs that all run, and any
  minimal-edit scored on `clone_count` accepts the cloning answer as solved-but-worse.
  Getting this wrong sent 25 verified puzzles for "repair" and damaged them; git restored
  every one, which is why content stays uncommitted until reviewed.
- **Deliberate ties live in `ALLOWED_TIES`** in `tools/audit-progression.py`, and
  `repair-content.py` parses that same list so there is one source, not two.
- **Node numbering comes from the deck's own pack.json**, never the manifest. A stale
  manifest count numbered new nodes over existing ones, duplicating ids and crashing the
  app on a duplicate dictionary key.
- **Test execution times out after 10s** (`crates/evaluator`). A concurrency puzzle can
  deadlock by design — the mpsc "forgot to drop the sender" answer blocks forever — and
  without the bound the linter waited with it, orphaning linters that burned CPU for hours.
- **Large decks chunk at 6 nodes** and auto-split on truncation; 12-18 node decks overran
  the output budget otherwise.
- Style and review-card checks run **inside** the repair loop, imported from
  `tools/check-style.py` so the generator cannot drift from the rule CI enforces.

**Proposed build approach** (awaiting user go): manifest-driven and reproducible —
`content/curriculum.json` declaring every planned deck (level, source segments, concepts,
status); `tools/extract-source.py` pulling teaching points from the cloned CR repo into
`bank/`; `tools/authoring.py` giving `lesson()`/`puzzle()`/`slot()` helpers so each deck is a
committed spec file under `tools/decks/` rather than a throwaway script; `tools/check-style.py`
enforcing the voice in CI. Build order: re-level to six tiers → fix Foundations → Everyday
gaps → Systems gaps → Mastery → review cards follow each batch.

## Progression quality bar

Every puzzle must survive these questions before publishing:

- Does it introduce exactly one new Rust instinct?
- Does difficulty increase smoothly from its predecessor?
- Is it distinct from its neighbours (not a re-skin)?
- Does it require only knowledge previously exercised?
- Is the optimal solution genuinely better, or merely shorter?
- Can it be solved by guessing? (If yes, the choice set is wrong.)

**Every puzzle trains a behaviour, not trivia.**

## Question-bank sourcing

Open material bootstraps the bank but always via **transformation, never import** — existing
exercises are written for keyboards and repositories, not phone interactions:

- **Comprehensive Rust** (google/comprehensive-rust, **Apache-2.0 for code, CC-BY-4.0 for
  prose**) — the primary structural source from 2026-08-07. Explicitly written for engineers
  already fluent in another language, which is RustChap's audience. Cloned to
  `bank/sources/comprehensive-rust` (gitignored). Neither licence is copyleft, so adapting it
  does not affect RustChap's Apache-2.0 + Commons Clause. Attribution per node via
  `source.origin = "comprehensive-rust"`; the outline/sequence itself is uncopyrightable
  ideas, but credit is given anyway. Do not imply Google endorsement.
- **Rustlings** (MIT) — concepts, compiler failures, minimal-repair patterns.
- **Exercism Rust track** (MIT repo, 99 exercises) — practice problems; its track is explicitly
  non-sequential, so progression is ours to design.
- **100 Exercises to Learn Rust** (Mainmatter) — strong progression and realistic ownership cases;
  check its licence before adapting content.
- Rust compiler UI tests, Clippy lint tests, The Rust Book, Rust by Example, Rust Quiz.
- Stack Overflow / forum questions and real-world open-source diffs (where a clone, allocation,
  lifetime, or bound was improved) — inspiration only, never copied content.

Every published puzzle carries a `source` record (origin, licence, attribution) — see
[puzzle-format](../architecture/puzzle-format.md). LLMs may generate variants, distractors, hints,
and explanations, but never decide correctness: the compiler, tests, Clippy, and static
instrumentation are the judges.
