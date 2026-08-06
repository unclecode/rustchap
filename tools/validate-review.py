#!/usr/bin/env python3
"""Validate content/review cards: shape, concept references, style rules.

Kept in Python (not the Rust linter) because review cards compile nothing;
they are display content. CI runs this next to the puzzle checks.
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REVIEW = ROOT / "content" / "review"
CONCEPTS = ROOT / "content" / "concepts"

KINDS = {"rule", "gotcha", "syntax", "error", "choice"}
ID_RE = re.compile(r"^[a-z0-9-]+\.(rule|gotcha|syntax|error|choice)\.[a-z0-9-]+$")

def main() -> int:
    known = {p.stem for p in CONCEPTS.glob("*.json")}
    errors, cards = [], []
    for path in sorted(REVIEW.glob("*.json")):
        card = json.loads(path.read_text())
        cid = card.get("id", path.stem)
        cards.append(card)
        if path.stem != cid:
            errors.append(f"{path.name}: filename does not match id {cid}")
        if not ID_RE.match(cid):
            errors.append(f"{cid}: id must be <concept>.<kind>.<slug>")
        if card.get("kind") not in KINDS:
            errors.append(f"{cid}: unknown kind {card.get('kind')!r}")
        elif not cid.startswith(card["concepts"][0] + "." + card["kind"] + "."):
            errors.append(f"{cid}: id must start with its first concept and kind")
        for concept in card.get("concepts", []):
            if concept not in known:
                errors.append(f"{cid}: unknown concept {concept!r}")
        title = card.get("title", "")
        if not (3 <= len(title) <= 44):
            errors.append(f"{cid}: title must be 3-44 characters")
        for field in ("prompt", "answer", "title"):
            text = card.get(field, "")
            if "—" in text or "–" in text:
                errors.append(f"{cid}: {field} contains a dash character we do not use")
            if len(text) < 10:
                errors.append(f"{cid}: {field} is too short")

    ids = [c["id"] for c in cards]
    for dup in {i for i in ids if ids.count(i) > 1}:
        errors.append(f"duplicate id: {dup}")

    for e in errors:
        print("error:", e)
    covered = {c for card in cards for c in card["concepts"]}
    print(f"review cards: {len(cards)} valid, {len(covered)} concepts covered")
    by_kind = {}
    for card in cards:
        by_kind[card["kind"]] = by_kind.get(card["kind"], 0) + 1
    print("by kind:", dict(sorted(by_kind.items())))
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
