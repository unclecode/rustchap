---
title: Curriculum
status: living
sources:
  - content/packs/move-or-borrow/puzzles/move-or-borrow.001.json
  - content/packs/remove-the-clone/puzzles/remove-the-clone.001.json
  - content/packs/repair-the-lifetime/puzzles/repair-the-lifetime.001.json
  - content/packs/build-the-iterator/puzzles/build-the-iterator.001.json
  - content/packs/design-the-api/puzzles/design-the-api.001.json
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

## v0.1 tracks — 5 × 8 = 40 puzzles

| Track | Trains |
|---|---|
| Move or borrow | moves vs borrows, when `&`/`&mut` suffices |
| Remove the clone | spotting and eliminating unnecessary `clone()`/allocation |
| Repair the lifetime | lifetime errors, elision, annotating only what's needed |
| Build the iterator | iterator pipelines, ownership variants (`iter`/`into_iter`/`iter_mut`) |
| Design the API | narrowest correct signatures, weakest sufficient bounds |

Eight puzzles per track, one linear path.

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

Ten tap-to-learn skills backing the puzzles' `concepts` references (linter-enforced): `move`,
`borrow`, `deref-coercion`, `clone`, `slice`, `lifetime`, `elision`, `iterator`, `zero-copy`,
`api-design`. Each is a one-line summary + 2–4 lecture paragraphs + a highlighted example,
written for an experienced programmer — the minimum needed to attempt the puzzle, never a course.
New puzzles should reference existing concepts where possible; add a new concept file only when a
genuinely new instinct appears.

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
