---
title: Puzzle format and content pipeline
status: backlog
sources: []
related:
  - architecture/evaluation.md
  - foundation/curriculum.md
  - foundation/interaction-types.md
---

# Puzzle format and content pipeline

The versioned puzzle JSON is the **platform-neutral contract** of the whole system — what makes a
future Android client possible without sharing UI code. Schema will live in `schemas/`
(`puzzle.schema.json`), validated by `crates/puzzle-schema/`, with content under `content/packs/`
and authoring tools in `tools/` (`puzzle-linter`, `source-importer`).

> **Agreed design, no schema frozen yet.** The JSON snippets below are drafts from planning; the
> real schema is authored at build-order Step 5 and versioned from day one (`schema_version`).

## Draft shape

```json
{
  "schema_version": 1,
  "id": "borrow.reborrow.017",
  "version": 1,
  "title": "Borrow Again",
  "track": "move-or-borrow",
  "concepts": ["mutable-borrow", "reborrow", "non-lexical-lifetimes"],
  "difficulty": 4,
  "interaction": {
    "type": "slot-selection",
    "slots": [{ "id": "argument", "choices": ["value", "&value", "&mut value"] }]
  },
  "goal": "Make both print statements valid.",
  "source_template": "...",
  "editable_regions": ["…"],
  "tests": ["..."],
  "valid_solutions": ["..."],
  "goals": { "must_compile": true, "max_clones": 0 },
  "scoring": {
    "primary": "clone_count",
    "secondary": ["token_edits"],
    "best_known": { "clone_count": 0, "token_edits": 1 }
  },
  "hints": ["..."],
  "explanation": "...",
  "prerequisites": ["…"],
  "source": { "origin": "rustlings", "license": "MIT", "attribution": "..." }
}
```

IDs are hierarchical (`track/concept.family.number`); puzzles are versioned independently of the
schema so a fixed puzzle doesn't invalidate stored progress silently.

## The puzzle linter (built before any UI)

`cargo run -p puzzle-linter -- content/packs/<pack>` must verify: schema validity, unique IDs,
valid prerequisites, editable slots exist, **every declared choice reconstructs valid source**, the
reference solution compiles, tests pass, **best-known scores are reproducible**, and
licence/attribution present. This is what keeps the content bank trustworthy.

## Ingestion pipeline (transform, never import)

```text
Find useful source exercise
→ identify the Rust-specific insight
→ reduce to one tiny challenge (5–15 lines)
→ redesign for phone interaction
→ define the replay metric
→ generate valid and invalid paths
→ compile every path against stable Rust
→ human review
```

## Per-puzzle publishing bar

Reference solution · best-known score · at least one realistic wrong answer · structured feedback ·
short hint · deeper explanation · mobile preview approval · compiler verification · licence record.

## Authoring workflow (Step 18)

Raw-JSON editing doesn't scale past the first puzzles. A small internal tool (CLI or local web UI)
supports: create-from-template, paste starter code, mark editable regions, define choices, add
tests, run all candidate solutions, inspect diagnostics, calculate scores, preview mobile
rendering, attach attribution, publish a puzzle version.

## Consumers of the contract

- iOS app: renders `interaction` + `source_template` as the token surface, submits operations.
- Evaluator: reconstructs source from `source_template` + operations, scores against `scoring`.
- Linter/CI: compiles all reference solutions and declared alternatives, verifies score
  reproducibility on every PR.
- Future Android client: same JSON, same API, rewritten presentation only.
