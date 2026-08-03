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
