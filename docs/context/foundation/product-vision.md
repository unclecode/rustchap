---
title: Product vision
status: foundational
sources: []
related:
  - foundation/core-loop.md
  - foundation/curriculum.md
  - roadmap/v0.1-scope.md
---

# Product vision

RustChap is a native iPhone puzzle game that trains **Rust instincts** in already-experienced
programmers — the Euclidea model applied to Rust semantics. It is built first for its own author
(a daily Euclidea player and experienced programmer learning Rust), with open-sourcing planned
once the core loop proves itself.

> **The promise is "Develop Rust instincts", not "Learn Rust".** The user already knows how to
> program. The product trains the reflexes Rust uniquely demands: predicting what the type system
> permits, expressing ownership correctly, and recognising the idiomatic solution — until borrows,
> lifetimes, traits, and iterators become almost perceptual.

## Why Euclidea is the model

Euclidea works because the problem *is* the interface: one bounded puzzle per screen, immediate
feedback, gradual concept unlocking, sessions short enough for casual daily play, and — critically —
a minimal-move score that makes you replay a solved puzzle to find the more elegant construction.
RustChap preserves every one of those properties:

- One puzzle at a time; solving unlocks the next.
- The compiler gives immediate, honest feedback.
- A measurable score ("3 edits, 1 clone — best known: 2 edits, 0 clones") creates natural replay.
- No chapters, videos, articles, dashboards, streak noise, or floating AI tutor.

Rust's equivalent of "find the elegant construction" is not algorithmic cleverness. It is: who owns
this value, why was it moved, can this borrow live that long, should this be `&T` / `&mut T` /
`Box<T>` / `Rc<T>`, can the type system encode the invariant.

## What RustChap is not

- Not a mobile code editor with lessons around it — full phone typing is the wrong primitive.
- Not a beginner course — syntax appears incidentally, never as the curriculum.
- Not a quiz app — prediction/multiple-choice puzzles exist only as supporting exercises.
- Not a generic algorithm site — puzzles that can be passed with ugly Python-shaped Rust are
  considered defective.

## Positioning against existing tools

Surveyed alternatives and why they fall short of the Euclidea feel: **Rustfinity** (closest match,
progressive puzzle tracks, but web-first), **Rustlings** (pedagogically excellent terminal workbook,
emotionally not addictive), **Exercism** (strong for comparing solutions after fundamentals),
**Codewars** (teaches algorithms, not Rust). None scores solutions on minimal-operation elegance —
the gap RustChap exists to fill. Rust is uniquely suited to this because the compiler already
exposes most of the game engine.

## Naming

The product name is **RustChap**. An earlier working name, "RustUp", was dropped because it
collides with `rustup`, the official Rust toolchain installer (App Store confusion plus Rust
Foundation trademark risk). The internal engine concept was drafted as "rust-instinct"; repo and
identifiers use `rustchap`.

## The larger opportunity

The engine is deliberately language-agnostic at the contract level (versioned puzzle JSON, remote
evaluation, metric-based scoring), so later packs could cover SQL, TypeScript types, Haskell types,
C++ memory, or regex. Rust is the correct first language and the sole focus until v0.1 ships.
