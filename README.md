# RustChap 🦀

**Learn Rust the way Euclidea teaches geometry: small puzzles with exact answers,
verified by the real compiler.**

I'm [Uncle Code](https://unclecode.com) ([@unclecode](https://x.com/unclecode)),
author of [Crawl4AI](https://github.com/unclecode/crawl4ai)
[![GitHub stars](https://img.shields.io/github/stars/unclecode/crawl4ai)](https://github.com/unclecode/crawl4ai).
I planned to rewrite Crawl4AI in Rust, and that meant making Rust second nature -
not vocabulary, instinct. I'm also a long-time fan of Euclidea; I've played it
through many times. So I built the same kind of game for the thing I needed to
learn, for myself first. This is it.

RustChap is a native iOS game for experienced programmers. One tiny program per
screen, constrained edits instead of typing: tap tokens, reorder statements, pick
the best implementation. Every legal answer to every puzzle was compiled ahead of
time with real `rustc` and Clippy, so every verdict is the compiler's truth - not
my opinion.

If you're a professional programmer coming from other languages and want Rust's
idioms, syntax, and concepts to become reflexes, this is a good place. Pull
requests are welcome - puzzles, lectures, and more.

**Available on the App Store** - download and play right now, or build it
yourself from this repo.

> Not "learn Rust". The promise is **develop Rust instincts**: predicting what the
> type system permits, expressing ownership correctly, recognising the idiomatic
> solution.

## How it plays

- **15 decks, one arc**: ownership → borrowing → lifetimes → slices → `Option`/
  `Result` → pattern matching → iterators → closures → traits → generics → smart
  pointers → interior mutability → API design → async → unsafe.
- **60+ puzzles**, each teaching exactly one instinct. Ranks are mechanical:
  Solved (compiles, tests pass) → Fluent → Optimal (match the star budget, like
  `0C·2E` - zero clones in two edits).
- **20 short lectures** in plain English - every deck opens with one.
- **A grounded AI tutor** that knows the puzzle on your screen. On-device by
  default (Apple Foundation Models); optionally bring your own OpenRouter key.
- **Fully offline.** No account, no ads, no tracking, no server.

## How it works

The puzzle JSON contract lives in [`schemas/`](schemas/) and is enforced by
[`crates/puzzle-schema`](crates/puzzle-schema). [`crates/evaluator`](crates/evaluator)
compiles every enumerated submission with the pinned toolchain; the
[`puzzle-linter`](tools/puzzle-linter) writes the verdicts into `outcomes/`
sidecars the app bundles. The iOS app ([`apps/ios`](apps/ios)) looks answers up
by a canonical operations hash - byte-identical between Rust and Swift. CI
recompiles every submission on each push; any verdict drift fails the build.

```text
apps/ios/                  SwiftUI iPhone app (Swift 6)
crates/puzzle-schema/      Puzzle JSON contract: types, validation, hashing
crates/evaluator/          Ops → source → rustc/clippy → verdict + metrics
services/api/              Axum API (built and tested; not deployed - v0.1 is serverless)
content/packs/             15 decks: puzzles, lectures, verified outcomes
content/concepts/          The tap-to-learn skill library
schemas/                   The platform-neutral JSON contract
tools/                     puzzle-linter, progression audit, ingestion
docs/context/              Living design fragments (start at its README)
```

## Building

```sh
cargo test --workspace                             # engine + contract tests
cargo run -p puzzle-linter -- --check \
  --concepts content/concepts content/packs/*/     # re-verify every answer
python3 tools/audit-progression.py                 # curriculum audit
# iOS app (requires Xcode):
xcodebuild -project apps/ios/RustChap.xcodeproj -target RustChap \
  -configuration Debug -sdk iphonesimulator build
```

## Contributing

Issues and pull requests are welcome - especially new puzzles and lectures.
Content must pass the linter (which recompiles every answer) and the progression
audit; the quality bar lives in
[`docs/context/foundation/curriculum.md`](docs/context/foundation/curriculum.md).
Every puzzle carries a `source` attribution. In Claude Code, `/rustchap-context`
loads the right design fragment for whatever you touch.

## License

Apache License 2.0 with the [Commons Clause](https://commonsclause.com)
condition: use, modify, and build RustChap for yourself, and contribute back -
but do not sell it or a product substantially derived from it. See
[LICENSE](LICENSE).

RustChap is an independent educational project, not affiliated with or endorsed
by the Rust Foundation. Ferris artwork by Karen Rustad Tölva (CC0).
