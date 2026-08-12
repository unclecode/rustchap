#!/usr/bin/env python3
"""Compile all committed content, then repair whatever fails.

`generate-deck.py --rounds 0` drafts without verifying, which is much faster when
producing many decks: one big compile at the end beats a compile after every
repair round of every deck. This is that end pass.

    python3 tools/repair-content.py --scan            # what is broken
    python3 tools/repair-content.py --fix             # repair it
    python3 tools/repair-content.py --fix --rounds 3

A puzzle is broken when the number of submissions that compile AND pass its
tests is not exactly one. Zero means it has no answer; more than one means it
has no single answer. Both are unplayable.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util as _ilu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = _ilu.spec_from_file_location("gd", f"{ROOT}/tools/generate-deck.py")
gd = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(gd)


def lint(packs: list[str]) -> str:
    return subprocess.run(
        ["cargo", "run", "-q", "-p", "puzzle-linter", "--release", "--",
         "--summary", "--concepts", f"{ROOT}/content/concepts",
         *[f"{ROOT}/content/packs/{p}/" for p in packs]],
        cwd=ROOT, capture_output=True, text=True).stdout


def interaction_of(deck: str, pid: str) -> str:
    try:
        return json.load(open(f"{ROOT}/content/packs/{deck}/puzzles/{pid}.json")
                         )["interaction"]["type"]
    except Exception:
        return "unknown"


def allowed_ties() -> set:
    """Puzzles whose tie is deliberate, read from the progression audit so there
    is one list, not two. Rewriting these would undo a documented decision."""
    import ast as _ast
    src = open(f"{ROOT}/tools/audit-progression.py").read()
    tree = _ast.parse(src)
    for node in tree.body:
        if isinstance(node, _ast.Assign) and getattr(node.targets[0], "id", "") == "ALLOWED_TIES":
            return set(_ast.literal_eval(node.value))
    return set()


def scan(packs: list[str]) -> dict[str, list[tuple[str, str]]]:
    """deck -> [(puzzle_id, what is wrong)]

    ONE rule for every interaction type: a puzzle needs at least one submission
    that compiles and passes, and exactly one that reaches OPTIMAL.

    Counting `solved` instead is wrong and cost real content on 2026-08-07.
    Plenty of puzzles are meant to have several working answers ranked against
    each other: `best-solution` offers three programs that all run, and any
    minimal-edit scored on `clone_count` accepts the cloning answer as solved
    but not optimal. Only puzzles scored on `token_edits` have exactly one
    passing answer, and there the optimal count says so anyway.
    """
    broken: dict[str, list[tuple[str, str]]] = {}
    ties = allowed_ties()
    out = lint(packs)
    for line in out.splitlines():
        m = re.search(r"([a-z0-9-]+)\.(\d+): (\d+) submissions? — (\d+) solved "
                      r"\((\d+) optimal", line)
        if m:
            deck, num = m.group(1), m.group(2)
            solved, optimal = int(m.group(4)), int(m.group(5))
            pid = f"{deck}.{num}"
            if solved == 0:
                broken.setdefault(deck, []).append(
                    (pid, "no submission compiles and passes the tests"))
            elif optimal != 1 and pid not in ties:
                broken.setdefault(deck, []).append(
                    (pid, f"{optimal} submissions reach the optimal score, so there is "
                          "no single best answer"))
        m = re.search(r"ERROR: ([a-z0-9-]+)\.(\d+): (.+)", line)
        if m:
            deck = m.group(1)
            broken.setdefault(deck, []).append((f"{deck}.{m.group(2)}", m.group(3)))
    return broken


def repair_deck(deck: str, problems: list[tuple[str, str]], rounds: int) -> dict:
    """Send the deck's broken puzzles back to the model until they verify."""
    pack_dir = f"{ROOT}/content/packs/{deck}"
    log = [f"[{deck}] {len(problems)} broken node(s)"]
    ids = [pid for pid, _ in problems]

    for rnd in range(1, rounds + 1):
        nodes = {pid: json.load(open(f"{pack_dir}/puzzles/{pid}.json")) for pid in ids}
        payload = [{"id": pid, "problem": why, "node": nodes[pid]}
                   for pid, why in problems if pid in nodes]
        prompt = f"""You wrote these puzzles for the RustChap deck "{deck}". The
compiler ran every combination of choices for each one. They FAILED.

{json.dumps(payload, indent=1, ensure_ascii=False)[:40000]}

Rewrite each one. Keep its title, its goal, and the misconception it teaches.
The rules that matter:

- Exactly ONE combination of choices may compile AND pass every test.
- Every other combination must fail for a reason a learner benefits from.
- Check each choice in your head: does it compile? does it pass the tests?
- Templates under 16 lines, 2 slots with 3 choices each.
- For best-solution, exactly one candidate may reach the optimal metric value.
- For block-arrangement, at most 5 blocks, and the given order must compile.
- Keep the same interaction type and the same JSON shape you were given.

Return {{"nodes": [{{"id": "<the same id>", "node": {{...the full node...}}}}]}}
"""
        try:
            fix, _ = gd.ask(prompt, gd.MODEL)
        except Exception as e:
            log.append(f"[{deck}] round {rnd}: model call failed - {e}")
            break

        changed = []
        for item in fix.get("nodes", []):
            pid = item.get("id")
            if pid not in nodes:
                continue
            new = item["node"]
            old = nodes[pid]
            # keep identity and provenance; only the puzzle body may change
            for key in ("id", "track", "version", "schema_version", "source", "concepts"):
                if key in old:
                    new[key] = old[key]
            json.dump(new, open(f"{pack_dir}/puzzles/{pid}.json", "w"),
                      indent=2, ensure_ascii=False)
            open(f"{pack_dir}/puzzles/{pid}.json", "a").write("\n")
            changed.append(pid)
        if not changed:
            log.append(f"[{deck}] round {rnd}: model returned nothing usable")
            break

        still = scan([deck]).get(deck, [])
        still = [(p, w) for p, w in still if p in ids]
        if not still:
            log.append(f"[{deck}] round {rnd}: all repaired")
            return {"deck": deck, "log": log, "fixed": len(ids), "left": 0}
        log.append(f"[{deck}] round {rnd}: {len(still)} still failing")
        problems, ids = still, [p for p, _ in still]

    return {"deck": deck, "log": log, "fixed": len(problems) and 0, "left": len(ids)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scan", action="store_true")
    ap.add_argument("--fix", action="store_true")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("decks", nargs="*")
    a = ap.parse_args()

    packs = a.decks or json.load(open(f"{ROOT}/content/packs/index.json"))["order"]
    print(f"compiling {len(packs)} deck(s)...", flush=True)
    broken = scan(packs)
    total = sum(len(v) for v in broken.values())
    print(f"\n{total} broken node(s) across {len(broken)} deck(s)")
    for deck, items in sorted(broken.items()):
        print(f"  {deck}: {len(items)}")
        for pid, why in items[:4]:
            print(f"     {pid}: {why}")

    if not a.fix or not broken:
        return 0

    print(f"\nrepairing with up to {a.rounds} round(s)...", flush=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = {ex.submit(repair_deck, d, items, a.rounds): d
                for d, items in broken.items()}
        for f in concurrent.futures.as_completed(futs):
            try:
                results.append(f.result())
            except Exception as e:
                results.append({"deck": futs[f], "log": [f"crashed: {e}"], "left": -1})
    for r in sorted(results, key=lambda x: x["deck"]):
        for line in r["log"]:
            print(" ", line)
    left = sum(max(0, r.get("left", 0)) for r in results)
    print(f"\n{left} node(s) still broken")
    return 0


if __name__ == "__main__":
    sys.exit(main())
