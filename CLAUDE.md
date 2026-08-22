# RustChap — project instructions

RustChap is a native iPhone puzzle game (Euclidea for Rust semantics) for training Rust instincts
in experienced programmers. Monorepo: SwiftUI app in `apps/ios`, Rust backend in `services/`,
shared crates in `crates/`, puzzle content in `content/`, the puzzle JSON contract in `schemas/`.

- **Orient first:** design decisions live as fragments in `docs/context/` (index:
  `docs/context/README.md`). Load the relevant fragment via `/rustchap-context` before changing a
  subsystem — do not re-derive decisions already made there.
- **Docs: before pushing, run `/rustchap-context sync`** — map changed sources → fragments,
  update + approve, commit docs together with the code.
- The project is pre-code: `architecture/` fragments are agreed design (`status: backlog`). When
  you implement a subsystem, re-anchor its fragment (`sources:` + symbols + `status: shipped`).
- `docs/archive/` is frozen provenance (the founding plan transcript) — never edit it and never
  treat it as current truth; `docs/context/` supersedes it.
- Product name is **RustChap** (`rustchap` in identifiers). The directory name `rustup` is
  historical; don't introduce new "rustup"/"rust-instinct" identifiers.

