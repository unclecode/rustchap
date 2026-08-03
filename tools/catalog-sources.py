#!/usr/bin/env python3
"""Catalog the fetched source banks (bank/sources) into bank/catalog.json.

Each candidate exercise gets: source, name, path, licence, and a suggested
RustChap deck. The catalog is the shopping list for annotation sessions —
regenerable working data, not content (bank/ is gitignored).
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "bank" / "sources"

# Source topic → our deck id. None = no deck yet / out of scope for now.
RUSTLINGS_TOPIC_TO_DECK = {
    "move_semantics": "move-or-borrow",
    "primitive_types": "move-or-borrow",
    "strings": "slices-and-views",
    "slices": "slices-and-views",
    "vecs": "build-the-iterator",
    "iterators": "build-the-iterator",
    "options": "option-and-result",
    "error_handling": "option-and-result",
    "enums": "pattern-matching",
    "structs": "pattern-matching",
    "if": "pattern-matching",
    "traits": "traits-and-bounds",
    "generics": "generics-and-dyn",
    "smart_pointers": "smart-pointers",
    "box": "smart-pointers",
    "rc": "smart-pointers",
    "arc": "smart-pointers",
    "cow": "smart-pointers",
    "closures": "closures",
    "threads": None,
    "lifetimes": "repair-the-lifetime",
    "clippy": "remove-the-clone",
    "conversions": "design-the-api",
}

EXERCISM_KEYWORD_TO_DECK = [
    (("borrow", "ownership"), "move-or-borrow"),
    (("string", "slice", "reverse", "acronym", "pangram"), "slices-and-views"),
    (("option", "result", "error"), "option-and-result"),
    (("iterator", "map", "filter", "series", "sum"), "build-the-iterator"),
    (("trait", "generic"), "traits-and-bounds"),
    (("match", "enum"), "pattern-matching"),
]


def rustlings():
    exercises_dir = SOURCES / "rustlings" / "exercises"
    for path in sorted(exercises_dir.rglob("*.rs")):
        topic = path.parent.name if path.parent != exercises_dir else path.stem
        deck = None
        for prefix, mapped in RUSTLINGS_TOPIC_TO_DECK.items():
            if topic.startswith(prefix) or path.stem.startswith(prefix):
                deck = mapped
                break
        yield {
            "source": "rustlings",
            "license": "MIT",
            "name": path.stem,
            "path": str(path.relative_to(ROOT)),
            "suggested_deck": deck,
        }


def exercism():
    practice = SOURCES / "exercism-rust" / "exercises" / "practice"
    for exercise_dir in sorted(p for p in practice.iterdir() if p.is_dir()):
        name = exercise_dir.name
        deck = None
        for keywords, mapped in EXERCISM_KEYWORD_TO_DECK:
            if any(k in name for k in keywords):
                deck = mapped
                break
        yield {
            "source": "exercism",
            "license": "MIT",
            "name": name,
            "path": str(exercise_dir.relative_to(ROOT)),
            "suggested_deck": deck,
        }


def main():
    if not SOURCES.exists():
        sys.exit("run tools/fetch-sources.sh first")
    candidates = list(rustlings()) + list(exercism())
    by_deck = {}
    for c in candidates:
        by_deck.setdefault(c["suggested_deck"] or "(unmapped)", []).append(c["name"])
    out = ROOT / "bank" / "catalog.json"
    out.write_text(json.dumps({"schema_version": 1, "candidates": candidates}, indent=2) + "\n")
    print(f"cataloged {len(candidates)} candidates → {out.relative_to(ROOT)}")
    for deck in sorted(by_deck):
        print(f"  {deck:22} {len(by_deck[deck])}")


if __name__ == "__main__":
    main()
