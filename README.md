# RustChap

Euclidea for Rust semantics — a native iPhone puzzle game that trains **Rust instincts** in
experienced programmers. One tiny program per screen, constrained edits instead of typing,
compile → score → retry for a cleaner solution → next.

> Not "learn Rust". The promise is **develop Rust instincts**: predicting what the type system
> permits, expressing ownership correctly, recognising the idiomatic solution.

## Status

Pre-code. The product contract, architecture, and build order are decided and documented in
[`docs/context/`](docs/context/README.md) — start there. The founding plan transcript is preserved
in [`docs/archive/plan_draft.md`](docs/archive/plan_draft.md).

## Layout

```text
apps/ios/                  SwiftUI iPhone app (Swift 6)
services/api/              Axum API (Rust)
services/compiler-worker/  Sandboxed rustc evaluation workers
crates/puzzle-schema/      Puzzle JSON schema types + validation
crates/evaluator/          Patch → source → compile → score
crates/metrics/            Solution metric analysers (clones, allocations, …)
content/packs/             Versioned puzzle content
schemas/                   puzzle.schema.json (the platform-neutral contract)
tools/                     puzzle-linter, source-importer, authoring tools
docs/context/              Living design fragments (see its README)
docs/archive/              Frozen provenance documents
```

## Working on RustChap

Project docs are load-on-demand fragments wired to source files. In Claude Code, use
`/rustchap-context` to orient and `/rustchap-context sync` to keep docs honest after changes.
