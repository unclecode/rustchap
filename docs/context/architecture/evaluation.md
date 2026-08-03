---
title: Evaluation pipeline
status: living
sources:
  - crates/evaluator/src/lib.rs
  - crates/evaluator/src/metrics.rs
  - crates/evaluator/src/rustc_json.rs
  - crates/evaluator/src/bin/evaluate.rs
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
  `clone_count` counts explicit copies (`.clone()`, `.to_owned()`, `.to_vec()`, `.cloned()` —
  extended 2026-08-03 so copying candidates can't tie zero-copy ones), `explicit_loops`,
  `mut_bindings`, `unsafe_blocks`; `token_edits` comes from operations without compiling;
  `clippy_warning_count` from the deny list.
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

## Serving layers (steps 12 + 14 shipped)

- **CLI** (`crates/evaluator/src/bin/evaluate.rs`): `evaluate <puzzle.json> < submission.json` →
  `EvalResult` JSON. Failed submissions exit 0 (a compile error is a result); only
  infrastructure errors exit 1.
- **API** (`services/api`): `POST /v1/puzzles/{id}/evaluate` runs sidecar → live cache → live
  compile, in that order — see [backend](backend.md). Router tests prove the live path agrees
  with precomputed verdicts.
- **Deferred to deployment (step 13/28)**: Docker worker isolation + job queue. In-process
  evaluation is sound while submissions are enumerable operations only.
