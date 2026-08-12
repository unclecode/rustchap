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

def check_concepts() -> list[str]:
    """Every concept needs a topic, and it must be one the order file lists."""
    errors = []
    order_path = CONCEPTS / "topics.json"
    if not order_path.exists():
        return ["content/concepts/topics.json is missing"]
    known_topics = set(json.loads(order_path.read_text())["topics"])
    for path in sorted(CONCEPTS.glob("*.json")):
        if path.name == "topics.json":
            continue
        concept = json.loads(path.read_text())
        topic = concept.get("topic")
        if not topic:
            errors.append(f"concept {concept.get('id', path.stem)}: missing topic")
        elif topic not in known_topics:
            errors.append(f"concept {concept['id']}: unknown topic {topic!r}")
    return errors


REQUIRED = ("id", "kind", "title", "concepts", "prompt", "answer")


def check_card(path, card, known) -> list[str]:
    """Every problem with one card. Never raises: a card missing a field must
    still produce a message, not abort the whole run before anything prints."""
    cid = card.get("id", path.stem)
    errors = []

    missing = [k for k in REQUIRED if k not in card]
    if missing:
        errors.append(f"{cid}: missing required field(s) {', '.join(missing)}")

    if path.stem != cid:
        errors.append(f"{path.name}: filename does not match id {cid}")
    if not ID_RE.match(cid):
        errors.append(f"{cid}: id must be <concept>.<kind>.<slug>")

    kind = card.get("kind")
    concepts = card.get("concepts") or []
    if kind not in KINDS:
        errors.append(f"{cid}: unknown kind {kind!r}")
    elif not concepts:
        errors.append(f"{cid}: concepts is empty, so the id cannot be checked")
    elif not cid.startswith(f"{concepts[0]}.{kind}."):
        errors.append(f"{cid}: id must start with its first concept and kind "
                      f"(expected {concepts[0]}.{kind}.…)")
    for concept in concepts:
        if concept not in known:
            errors.append(f"{cid}: unknown concept {concept!r}")

    title = card.get("title", "")
    if not (3 <= len(title) <= 44):
        errors.append(f"{cid}: title must be 3-44 characters, this one is {len(title)}")
    for field in ("prompt", "answer", "title"):
        text = card.get(field) or ""
        if "—" in text or "–" in text:
            errors.append(f"{cid}: {field} contains a dash character we do not use")
        if len(text) < 10:
            errors.append(f"{cid}: {field} is too short")
    return errors


def main() -> int:
    known = {p.stem for p in CONCEPTS.glob("*.json")} - {"topics"}
    errors, cards = [], []
    for path in sorted(REVIEW.glob("*.json")):
        try:
            card = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            errors.append(f"{path.name}: invalid JSON at line {e.lineno} - {e.msg}")
            continue
        cards.append(card)
        try:
            errors.extend(check_card(path, card, known))
        except Exception as e:                      # a checker bug must not hide the rest
            errors.append(f"{path.name}: checker crashed - {type(e).__name__}: {e}")

    errors.extend(check_concepts())

    ids = [c.get("id") for c in cards if c.get("id")]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        errors.append(f"duplicate id: {dup}")

    for e in errors:
        print("error:", e)

    covered = {c for card in cards for c in (card.get("concepts") or [])}
    by_kind = {}
    for card in cards:
        by_kind[card.get("kind", "?")] = by_kind.get(card.get("kind", "?"), 0) + 1
    print(f"review cards: {len(cards)} checked, {len(covered)} concepts covered")
    print(f"concepts: {len(known)} tagged with a topic")
    print("by kind:", dict(sorted(by_kind.items())))
    if errors:
        print(f"\nFAILED with {len(errors)} error(s) - all listed above")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
