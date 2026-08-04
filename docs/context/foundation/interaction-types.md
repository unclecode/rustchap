---
title: Interaction types
status: foundational
sources: []
related:
  - foundation/core-loop.md
  - architecture/ios-app.md
  - architecture/puzzle-format.md
---

# Interaction types

Puzzles never require normal phone typing — punctuation, cursor movement, and selection are hostile
on a phone even for experts. Every interaction manipulates structured tokens.

## The four v0.1 interaction types

Only these ship in v0.1 (schema `interaction.type` values are illustrative until the schema is
frozen):

1. **Slot selection** (`slot-selection`) — tap a blank/slot, pick the missing token or type from a
   small choice tray. E.g. fill `x: ___, y: ___) -> ___` in a lifetimes signature with `&'a str`.
   Tests language knowledge, not keyboard tolerance.
2. **Minimal edit** (`minimal-edit`) — modify the fewest marked tokens to make broken code compile
   or meet a goal (e.g. change `print_name(name)` to `print_name(&name)` plus the signature).
   Scored by edit count: 4 edits valid, 2 efficient, 1 optimal. Closest to Euclidea.
3. **Block arrangement** (`block-arrangement`) — order draggable fragments (`.iter()`,
   `.filter(...)`, `.map(...)`, `.collect::<Vec<_>>()`) into a pipeline, then edit only expressions
   inside them.
4. **Best solution** (`best-solution`) — choose or construct the preferable implementation among
   several compiling candidates, under a stated goal: no allocation, no cloning, reusable input,
   thread-safe, zero-copy, minimal dynamic dispatch.

## The fifth type: lessons (added 2026-08-04, from the device review round)

5. **Lesson** (`lesson`) — a **reading node**, Euclidea's learning-challenge idea: short prose +
   highlighted code sections, completed by a "Got it" tap, no evaluation. Lessons are ordinary
   curriculum entries in `pack.order`, freely interleaved (`puzzle - puzzle - lecture - puzzle…`)
   and placed **after** first contact with the material — the puzzles before create the question,
   the lecture answers it, the puzzles after cash it in. The next puzzles ARE the comprehension
   check; dedicated check questions would be another interaction type later.

## Deferred types (designed, not in v0.1)

- **Choose the signature** — given implementation and usage, build the narrowest correct API from
  pieces like `String` / `&str` / `&String` / `impl AsRef<str>` / `Cow<'a, str>`.
- **Predict the compiler** — will it compile; if not, tap the responsible line and pick the error
  class (move / borrow conflict / lifetime / trait not implemented). Supporting exercise only —
  centering these turns the product into a quiz app.
- **Ownership timeline** — values and borrows as movable objects on a timeline; invalid borrow
  combinations visibly collide. The one interaction where mobile beats desktop coding, because
  ownership is spatial and temporal (RustViz-style pedagogy research supports visualising
  ownership rather than relying on compiler prose).
- **Type inference puzzles** — pick the `collect::<____>()` turbofish, or identify which
  constraints force each candidate inferred type.
- **Refactor under constraints** — e.g. "remove the allocation without changing behaviour" by
  editing only the return type and final expression.
- **Trait-bound construction** — assemble the weakest sufficient bound for
  `fn display_all<T: ______>` from pieces like `Display` / `Debug` / `Clone` / `Copy`.

Tiny free-keyboard input may be added later where it genuinely improves a specific puzzle — never
as the default mechanism.

## Why constrained editing is load-bearing

Constrained edits are not just mobile UX. They are what makes the whole system tractable:

- simpler, faster interactions on a phone
- deterministic scoring (the edit space is enumerable)
- fast compilation (one known template per puzzle)
- easy sandboxing (no arbitrary programs)
- validation of alternate answers at authoring time

See [evaluation](../architecture/evaluation.md) for how the structured-patch contract depends on
this, and [puzzle-format](../architecture/puzzle-format.md) for how editable regions are declared.
