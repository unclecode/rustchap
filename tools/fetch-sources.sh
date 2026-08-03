#!/usr/bin/env bash
# Fetch (or update) the open-source question banks we ingest from.
# Everything lands in bank/sources/ (gitignored — raw material, not our content).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/bank/sources"
mkdir -p "$DIR"

fetch() {
  local name="$1" url="$2"
  if [ -d "$DIR/$name/.git" ]; then
    git -C "$DIR/$name" pull --quiet --depth 1 2>/dev/null || true
    echo "updated  $name"
  else
    git clone --quiet --depth 1 "$url" "$DIR/$name"
    echo "cloned   $name"
  fi
}

fetch rustlings https://github.com/rust-lang/rustlings.git
fetch exercism-rust https://github.com/exercism/rust.git

echo
echo "rustlings exercises:  $(find "$DIR/rustlings/exercises" -name '*.rs' | wc -l | tr -d ' ')"
echo "exercism exercises:   $(ls "$DIR/exercism-rust/exercises/practice" | wc -l | tr -d ' ')"