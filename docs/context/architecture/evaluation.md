---
title: Evaluation pipeline
status: backlog
sources:
  - crates/puzzle-schema/src/ops.rs
  - schemas/outcomes.schema.json
related:
  - architecture/backend.md
  - architecture/puzzle-format.md
  - foundation/core-loop.md
---

# Evaluation pipeline

How a submitted answer becomes a verdict and a score. Spans `crates/evaluator/`, `crates/metrics/`,
and `services/compiler-worker/`.

> **Agreed design, no code yet.** The evaluator is built first as a local CLI (before the API), then
> wrapped by workers. When code lands, point `sources:` at it and flip `status`.

## Contract: structured patches, never source code

The iPhone **does not compile Rust locally** (shipping rustc in an iOS app is huge, slow, and
pointless given constrained edits) and **never sends free-form source**. It submits operations
against a puzzle's declared editable regions:

```json
{
  "puzzle_id": "ownership.borrow.001",
  "puzzle_version": 1,
  "operations": [ { "slot_id": "argument", "choice": "&name" } ]
}
```

There is deliberately no generic "compile Rust" endpoint — only `puzzle_id + approved structured
operations`. This yields simpler mobile UX, fast compiles, easy sandboxing, deterministic scoring,
and a sharply reduced attack surface.

## Pipeline

```text
Structured patch
→ validate permitted operations
→ reconstruct full source from the puzzle template
→ rustc --error-format=json
→ run tests
→ Clippy (when the puzzle requires it)
→ metric analyser
→ compare with best-known scores
→ structured result
```

Success output shape: `{status, score: {clone_count, token_edits, …}, rank, diagnostics: []}`.
Failure output maps rustc JSON diagnostics (rustc officially supports structured JSON output with
source spans) into app-controlled categories pointing at tokens:

```json
{ "category": "borrow_conflict", "message": "A mutable borrow is still active.",
  "token_ids": ["token_12", "token_27"], "rust_code": "E0502" }
```

Raw compiler prose is preserved behind a "Compiler details" disclosure, never the primary UX.

## Compiler workers

Compilation runs separately from the API: `API → job queue → ephemeral worker`. Each worker: no
network, read-only base filesystem, temporary writable dir, strict CPU/memory limits, execution
timeout, fixed stable Rust toolchain, dependency allowlist, process isolation. Docker suffices for
MVP; Firecracker microVMs or gVisor only if free-form code ever becomes a feature.

## Caching — the instant-feel third layer

Cache key (canonicalization shipped in `puzzle-schema`: `ops::ops_hash` over
`ops::normalized_ops_json`):

```text
toolchain + puzzle_version + ops_hash
```

Most wrong *and* optimal answers recur across users; Redis answers repeats without invoking the
compiler, and popular puzzles should converge to mostly cache hits.

**Decided: precomputed outcomes sidecar.** Because edits are constrained, the legal submission
space is finite (≤ `MAX_SUBMISSION_SPACE` = 512, enforced by `validate_puzzle`). The linter
evaluates the whole space up front into `outcomes.json` (`ops_hash → EvalResult`). The app bundles
it — Milestone-1 offline evaluation is exact, not mocked — and the server uses it as a warm cache,
so live compilation only ever confirms what precomputation already knows. Combined with client-side
validation and optimistic animation (see [ios-app](ios-app.md)), the target is **zero perceived
waiting**, not merely "fast compilation".

## Judgement rule

> LLMs may generate puzzle variants, distractors, hints, and explanations — but correctness is
> decided only by the compiler, tests, Clippy, and static instrumentation. No model ever grades an
> answer.
