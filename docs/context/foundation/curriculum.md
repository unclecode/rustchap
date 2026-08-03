---
title: Curriculum
status: foundational
sources: []
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

Eight puzzles per track, one linear path. The first five hand-authored puzzles (one per track)
deliberately exercise the whole engine: a compile failure, multiple valid answers, a measurable
optimal answer, a Clippy-based result, and an answer requiring runtime tests.

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
