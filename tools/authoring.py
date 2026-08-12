"""Deck authoring helpers — the boilerplate, so deck specs stay pure content.

A deck spec under `tools/decks/<deck-id>.py` imports this, describes its nodes,
and calls `write_deck()`. Specs are committed, so any deck can be regenerated or
revised later. Run one with:

    python3 tools/build-deck.py <deck-id>

The five interaction types mirror `schemas/puzzle.schema.json`:

    lesson()           reading node, no evaluation
    minimal_edit()     tap tokens to repair code (slots carry `original`)
    slot_selection()   fill blank slots from a tray (`original` may be null)
    best_solution()    pick the best of N complete programs
    block_arrangement()  order the blocks into a pipeline

Every node needs a `source` record. Use `SOURCES[...]` or pass your own.
"""

from __future__ import annotations

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SOURCES = {
    "comprehensive-rust": lambda where: {
        "origin": "comprehensive-rust",
        "license": "CC-BY-4.0",
        "attribution": f"adapted from {where}",
    },
    "rustlings": lambda where: {
        "origin": "rustlings",
        "license": "MIT",
        "attribution": f"adapted from {where}",
    },
    "exercism": lambda where: {
        "origin": "exercism",
        "license": "MIT",
        "attribution": f"adapted from {where}",
    },
    "original": lambda where=None: {"origin": "original", "license": None,
                                    "attribution": None},
}


# ----------------------------------------------------------------- sections
def prose(text: str) -> dict:
    """A paragraph of lecture text. Renders inline markdown, so use backticks."""
    return {"kind": "prose", "text": text}


def code(source: str, caption: str) -> dict:
    """A snippet with a one-line caption underneath."""
    return {"kind": "code", "code": source, "caption": caption}


# -------------------------------------------------------------------- slots
def slot(sid: str, label: str, choices: list[str], original: str | None = None) -> dict:
    """One tappable slot. `original` is the token as written (minimal-edit) or
    None for a blank to fill (slot-selection). The first choice is NOT assumed
    correct — the linter compiles every combination and finds out."""
    return {
        "id": sid,
        "original": original,
        "label": label,
        "choices": [{"id": f"{sid[:2]}{i + 1}", "text": t} for i, t in enumerate(choices)],
    }


# -------------------------------------------------------------------- nodes
def _base(deck: str, num: str, title: str, goal: str, concepts: list[str],
          difficulty: int, source: dict, prerequisites: list[str] | None) -> dict:
    return {
        "schema_version": 1,
        "id": f"{deck}.{num}",
        "version": 1,
        "title": title,
        "track": deck,
        "concepts": concepts,
        "difficulty": difficulty,
        "goal": goal,
        "prerequisites": prerequisites or [],
        "source": source,
    }


def lesson(num: str, title: str, goal: str, concepts: list[str],
           sections: list[dict], *, source: dict,
           prerequisites: list[str] | None = None) -> dict:
    """A reading node. Keep it to ONE idea — the 2026-08-07 review found that
    lectures teaching five things at once are where readers fall off."""
    node = _base("", num, title, goal, concepts, 1, source, prerequisites)
    node["interaction"] = {"type": "lesson", "sections": sections}
    node["hints"] = []
    node["explanation"] = goal
    return node


def _scored(node: dict, template: str, interaction: dict, tests: list[str],
            metrics: list[str], primary: str, fluent: dict, optimal: dict,
            secondary: list[str], hints: list[str], explanation: str) -> dict:
    if template is not None:
        node["template"] = template
    node["interaction"] = interaction
    node["evaluation"] = {"tests": tests, "metrics": metrics}
    node["scoring"] = {"primary": primary, "secondary": secondary,
                       "fluent": fluent, "optimal": optimal}
    node["hints"] = hints
    node["explanation"] = explanation
    return node


def minimal_edit(num, title, goal, concepts, difficulty, template, slots, tests,
                 hints, explanation, *, source, fluent=None, optimal=None,
                 metrics=None, primary="token_edits", secondary=None,
                 prerequisites=None) -> dict:
    """Repair working-but-wrong code by tapping tokens. Slots carry `original`."""
    node = _base("", num, title, goal, concepts, difficulty, source, prerequisites)
    edits = {"token_edits": len(slots)}
    return _scored(node, template, {"type": "minimal-edit", "slots": slots}, tests,
                   metrics or ["token_edits"], primary,
                   fluent or edits, optimal or edits, secondary or [],
                   hints, explanation)


def slot_selection(num, title, goal, concepts, difficulty, template, slots, tests,
                   hints, explanation, *, source, primary, fluent, optimal,
                   metrics=None, secondary=None, prerequisites=None) -> dict:
    """Fill blanks from a tray. Scored on a real metric (clones, loops, mut...)."""
    node = _base("", num, title, goal, concepts, difficulty, source, prerequisites)
    return _scored(node, template, {"type": "slot-selection", "slots": slots}, tests,
                   metrics or [primary], primary, fluent, optimal,
                   secondary or [], hints, explanation)


def best_solution(num, title, goal, concepts, difficulty, candidates, tests,
                  hints, explanation, *, source, primary, fluent, optimal,
                  metrics=None, secondary=None, prerequisites=None) -> dict:
    """Pick the best of N complete programs. `candidates` is [(id, code), ...]."""
    node = _base("", num, title, goal, concepts, difficulty, source, prerequisites)
    interaction = {"type": "best-solution",
                   "candidates": [{"id": i, "code": c} for i, c in candidates]}
    return _scored(node, None, interaction, tests,
                   metrics or [primary], primary, fluent, optimal,
                   secondary or [], hints, explanation)


def block_arrangement(num, title, goal, concepts, difficulty, prefix, blocks,
                      suffix, tests, hints, explanation, *, source, primary,
                      fluent, optimal, metrics=None, secondary=None,
                      prerequisites=None) -> dict:
    """Order the blocks. `blocks` is [(id, text), ...] in CORRECT order — the
    app shuffles for the player, and the linter permutes to find what compiles."""
    node = _base("", num, title, goal, concepts, difficulty, source, prerequisites)
    interaction = {"type": "block-arrangement", "fixed_prefix": prefix,
                   "blocks": [{"id": i, "text": t} for i, t in blocks],
                   "fixed_suffix": suffix}
    return _scored(node, None, interaction, tests,
                   metrics or [primary], primary, fluent, optimal,
                   secondary or [], hints, explanation)


def _from_git(rel_path: str) -> str:
    """Last committed version of a file that no longer exists on disk."""
    import subprocess
    sha = subprocess.run(["git", "log", "--all", "--format=%H", "-1", "--", rel_path],
                         cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if not sha:
        raise SystemExit(f"reuse(): {rel_path} is neither on disk nor in git history")
    return subprocess.run(["git", "show", f"{sha}:{rel_path}"],
                          cwd=ROOT, capture_output=True, text=True, check=True).stdout


def reuse(old_id: str, num: str, *, goal: str | None = None,
          explanation: str | None = None, hints: list[str] | None = None,
          title: str | None = None, concepts: list[str] | None = None) -> dict:
    """Carry an already-verified puzzle into a new deck, patching only its PROSE.

    Template, slots, tests and scoring come across untouched, so the node keeps
    its compile-verified outcomes. Use this when a deck is being restructured or
    its writing rewritten — which is almost always the case, since the puzzles
    were rarely the problem.
    """
    track, _ = old_id.rsplit(".", 1)
    rel = f"content/packs/{track}/puzzles/{old_id}.json"
    path = os.path.join(ROOT, rel)
    if os.path.exists(path):
        node = json.load(open(path))
    else:
        # The source deck was retired (a split or a rename). Read it back out of
        # git so the spec stays re-runnable and the provenance stays honest.
        node = json.loads(_from_git(rel))
    node["id"] = f".{num}"
    if goal is not None:
        node["goal"] = goal
    if explanation is not None:
        node["explanation"] = explanation
    if hints is not None:
        node["hints"] = hints
    if title is not None:
        node["title"] = title
    if concepts is not None:
        node["concepts"] = concepts
    return node


# -------------------------------------------------------------------- write
def concept(cid: str, title: str, topic: str, summary: str,
            lecture: list[str], example_code: str, example_caption: str) -> dict:
    return {"schema_version": 1, "id": cid, "title": title, "topic": topic,
            "summary": summary, "lecture": lecture,
            "example": {"code": example_code, "caption": example_caption}}


def _dump(path: str, obj) -> None:
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as fh:
        json.dump(obj, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def write_deck(deck_id: str, nodes: list[dict], *, concepts: list[dict] | None = None) -> None:
    """Write every node, fix up ids/tracks, and set the pack order.

    The pack.json must already exist (created with the six-level structure), so
    a deck's title, icon, accent and level stay put across regenerations.
    """
    pack_path = os.path.join(ROOT, f"content/packs/{deck_id}/pack.json")
    if not os.path.exists(pack_path):
        raise SystemExit(f"no pack.json for {deck_id} — add it to the manifest first")
    pack = json.load(open(pack_path))

    order = []
    for i, node in enumerate(nodes, start=1):
        num = node["id"].split(".")[-1] if node["id"] else f"{i:03d}"
        node["id"] = f"{deck_id}.{num}"
        node["track"] = deck_id
        order.append(node["id"])
        _dump(f"content/packs/{deck_id}/puzzles/{node['id']}.json", node)

    pack["order"] = order
    _dump(f"content/packs/{deck_id}/pack.json", pack)

    # Renumbering leaves orphans behind — a puzzle file that is no longer in the
    # order, or an outcomes file for a node that is now a lecture. Both make the
    # linter warn, so clear them here rather than by hand.
    keep = set(order)
    for sub in ("puzzles", "outcomes"):
        d = os.path.join(ROOT, f"content/packs/{deck_id}/{sub}")
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            node_id = fn[:-5]
            stale = node_id not in keep
            if sub == "outcomes" and not stale:
                node = next(n for n in nodes if n["id"] == node_id)
                stale = node["interaction"]["type"] == "lesson"
            if stale:
                os.remove(os.path.join(d, fn))
                print(f"  removed stale {sub}/{fn}")

    for c in concepts or []:
        _dump(f"content/concepts/{c['id']}.json", c)

    lessons = sum(1 for n in nodes if n["interaction"]["type"] == "lesson")
    print(f"{deck_id}: {len(nodes)} nodes ({lessons} lectures, "
          f"{len(nodes) - lessons} puzzles)"
          + (f", {len(concepts)} concepts" if concepts else ""))
