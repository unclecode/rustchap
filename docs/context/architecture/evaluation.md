---
title: Evaluation pipeline
status: living
sources:
  - crates/evaluator/src/lib.rs
  - crates/evaluator/src/metrics.rs
  - crates/evaluator/src/rustc_json.rs
  - crates/puzzle-schema/src/ops.rs
  - tools/puzzle-linter/src/lib.rs
  - tools/puzzle-linter/src/main.rs
  - schemas/outcomes.schema.json
related:
  - architecture/backend.md
  - architecture/puzzle-format.md
  - foundation/core-loop.md
---

# Evaluation pipeline

How a submitted answer becomes a verdict and a score. The **engine is shipped** as the
`evaluator` crate and its first consumer, the **puzzle linter** (`tools/puzzle-linter`); the
remote pieces (workers, queue, API) are still pending.

## Contract: structured patches, never source code

The iPhone does not compile Rust locally and never sends free-form source — only
`puzzle_id + operations` against declared editable regions. There is deliberately no generic
"compile Rust" endpoint. This yields fast compiles, easy sandboxing, deterministic scoring, and a
sharply reduced attack surface.

## The engine (shipped: `crates/evaluator`)

`evaluator::evaluate(puzzle, operations, toolchain)` is deterministic for a given
(puzzle, ops, toolchain) and runs:

```text
reconstruct_with_spans          (puzzle-schema; illegal ops → status "invalid", not an error)
→ rustc --error-format=json     (--test harness when tests exist; lib typecheck when no main)
→ run the test binary           (failure → status "test_failure")
→ clippy-driver                 (only when clippy_warning_count is scored; deny-list matching)
→ metrics::compute              (syntactic counts over Reconstruction::user_text)
→ rank_for                      (Optimal / Fluent / Solved via threshold maps; empty map never awards)
```

- **Diagnostics translation** (`rustc_json.rs`): rustc JSON errors → app categories
  (`category_for`: E0382→`move_error`, E0502→`borrow_conflict`, E0106/E0597→`lifetime_error`,
  E0277→`trait_not_implemented`, …), with primary spans mapped back to the slot/block the user
  touched via `Reconstruction::regions_overlapping`. Raw prose stays behind "Compiler details".
- **Metrics** (`metrics.rs`): word-boundary counting over user-controlled text only —
  `clone_count` (`.clone()`/`.to_owned()`), `explicit_loops`, `mut_bindings`, `unsafe_blocks`;
  `token_edits` comes from operations without compiling; `clippy_warning_count` from the deny list.
- **Toolchain** (`Toolchain`): rustc/clippy-driver from PATH, edition 2024, and an explicit
  `linker` picked up from `$CC` — cargo config does not apply to direct rustc calls, and on dev
  machines PATH's `cc` may not be a compiler (see the cc-alias note in ~/.cargo/config.toml).

## The linter (shipped: `tools/puzzle-linter`)

`cargo run -p puzzle-linter -- [--check] [--skip-eval] <pack-dir>...` →
`lint_pack`: pack structure (ids, order, prerequisites-point-backwards, `validate_puzzle`), then
evaluates **every** enumerated submission and writes `outcomes/<puzzle_id>.json`. A puzzle fails
the lint unless ≥1 submission solves and ≥1 reproduces the declared optimal. `--check` re-evaluates
and diffs against stored sidecars (CI mode); `--skip-eval` is structure-only.

## Precomputed outcomes = Milestone-1 evaluation

Because the legal space is finite (≤ `MAX_SUBMISSION_SPACE` = 512), the sidecar
(`ops_hash → EvalResult`) makes on-device evaluation **exact and offline** — not a mock. Cache key
everywhere: `toolchain + puzzle_version + ops_hash` (`puzzle-schema::ops`). The server later uses
the same sidecars as a warm cache; live compilation only confirms what precomputation knows.

## Still pending (build-order steps 13–15)

Compiler workers (Docker: no network, read-only fs, CPU/memory limits, timeout, fixed toolchain),
the job queue, and the Axum API endpoint wrapping this same `evaluate` call. A thin CLI wrapper
(step 12) is also trivial now — the engine is the library.
