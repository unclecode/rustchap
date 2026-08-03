---
title: Core loop and scoring
status: foundational
sources: []
related:
  - foundation/interaction-types.md
  - architecture/evaluation.md
  - foundation/product-vision.md
---

# Core loop and scoring

The atomic interaction: **understand a tiny program, modify one constrained part, compile, then
optimise your solution.** Everything else in the product serves this loop.

## The puzzle screen

Each puzzle occupies exactly one screen:

1. A precise goal (e.g. "Make both calls valid without cloning")
2. A small Rust fragment, usually 5–15 lines
3. A constrained editing mechanism (see [interaction-types](interaction-types.md))
4. Run
5. Result, compiler feedback, and score
6. Retry for a cleaner solution
7. Next puzzle

The reference interface sketch is deliberately minimal — title, code fragment, goal, Run button,
your score vs best known. Swipe left for the explanation, swipe up for the next puzzle. Nothing else.

## Scoring model

Never a single generic "efficiency" number — that becomes arbitrary. Each puzzle declares **one
primary metric**, optionally secondary metrics, drawn from a fixed vocabulary:

```text
Token edits · Allocations · Clones · Explicit loops · Temporary values · Mutable bindings
Runtime complexity · Memory footprint · Unsafe blocks · Trait-bound strength · API flexibility
```

Three completion levels (no stars):

| Level | Meaning | Example |
|---|---|---|
| **Solved** | Compiles and passes tests | any valid answer |
| **Fluent** | Meets the puzzle's quality bar | 0 clones |
| **Optimal** | Matches the best-known score | 0 clones, 1 edit |

Replay is driven by showing the gap, Euclidea-style:

```text
Your solution: 3 edits, 1 clone
Known best:    2 edits, 0 clones
```

> **Only claim optimality when the objective is mechanically measurable.** Rust often has several
> equally legitimate solutions depending on readability and API intent. "Optimal" must never rest
> on taste; if a puzzle's best answer is debatable, its primary metric is wrong.

## Feedback rules

- Compiler diagnostics are translated into the puzzle's visual language (categories like
  `borrow_conflict` pointing at specific tokens), not dumped as prose. Raw rustc output stays
  available behind a "Compiler details" disclosure.
- Compilation alone is too weak a success criterion — quality goals (no allocation, no cloning,
  zero-copy, minimal dynamic dispatch) are first-class puzzle objectives.
- The target for evaluation latency is **zero perceived waiting**, achieved by local validation,
  optimistic animation, and server-side submission caching (see
  [evaluation](../architecture/evaluation.md)).

## The success signal

The strongest product metric is not completion. It is: **after solving a puzzle, does the user
replay it to reach Fluent or Optimal?** The first gate before building any infrastructure:
"Would you voluntarily play five puzzles from the toilet without anyone reminding you?"
