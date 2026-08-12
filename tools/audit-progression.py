#!/usr/bin/env python3
"""Step-23 progression audit over the whole bank.

Reads packs + outcomes and flags:
  - difficulty drops along a deck's order (ramp should be ~monotonic)
  - guessable-to-Optimal puzzles (optimal rate >= 50% of the space) — the
    game is rank-seeking, so optimal-rate is the guessability that matters
  - deliberate ties live in ALLOWED_TIES with their justification
  - decks whose opener declares prerequisites
Prints a per-deck table and a flag list. Exit 1 only on hard flags
(guessable / opener-with-prereqs); ties and difficulty notes are review items.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKS = ROOT / "content" / "packs"

ALLOWED_TIES = {
    # both answers genuinely idiomatic; explanation says so explicitly
    "pattern-matching.002": "named variant vs wildcard — future-proofing is unmeasurable",
    "pattern-matching.003": "match vs if let — equally idiomatic",
    "strings-basics.002": "literal &str vs &String via deref coercion — both correct, lesson says so",
    "control-flow.003": "1..=5 vs 1..6 — same range, explanation says either earns the star",
    "control-flow.006": "_ vs a named binding — both are catch-all arms, explanation says so",
}

hard_flags, review = [], []
index = json.loads((PACKS / "index.json").read_text())

print(f"{'deck':22} {'n':>2}  {'diff ramp':12} {'space':>5} {'solve%':>6}  optimal-ties")
for deck in index["order"]:
    pack_file = PACKS / deck / "pack.json"
    if not pack_file.exists():
        continue
    pack = json.loads(pack_file.read_text())
    if not pack["order"]:
        print(f"{deck:22} {'0':>2}  (planned)")
        continue

    diffs, ramp_display, total_space, total_solved, ties = [], [], 0, 0, []
    for pos, pid in enumerate(pack["order"]):
        puzzle = json.loads((PACKS / deck / "puzzles" / f"{pid}.json").read_text())
        if puzzle["interaction"]["type"] == "lesson":
            # Reading node: no outcomes, no solve stats, transparent to the
            # difficulty ramp (its difficulty is not a challenge level).
            ramp_display.append("L")
            if pos == 0 and puzzle["prerequisites"]:
                hard_flags.append(f"{pid}: deck opener declares prerequisites")
            continue
        outcomes = json.loads((PACKS / deck / "outcomes" / f"{pid}.json").read_text())
        diffs.append(puzzle["difficulty"])
        ramp_display.append(str(puzzle["difficulty"]))
        space = len(outcomes["outcomes"])
        solved = sum(1 for r in outcomes["outcomes"].values() if r["status"] == "solved")
        optimal = sum(1 for r in outcomes["outcomes"].values() if r.get("rank") == "optimal")
        total_space += space
        total_solved += solved
        if puzzle["interaction"]["type"] != "best-solution":
            if optimal / space >= 0.5:
                if pid in ALLOWED_TIES:
                    review.append(f"{pid}: allowed tie — {ALLOWED_TIES[pid]}")
                else:
                    hard_flags.append(f"{pid}: guessable to Optimal — {optimal}/{space}")
            elif solved / space > 0.6:
                review.append(f"{pid}: high solve rate {solved}/{space}")
        if optimal > 1:
            ties.append(f"{pid}×{optimal}")
        if pos == 0 and puzzle["prerequisites"]:
            hard_flags.append(f"{pid}: deck opener declares prerequisites")
        if len(diffs) > 1 and diffs[-1] < diffs[-2] - 1:
            review.append(f"{pid}: difficulty drops {diffs[-2]}→{diffs[-1]}")

    ramp = "".join(ramp_display)
    print(f"{deck:22} {len(ramp_display):>2}  {ramp:12} {total_space:>5} {100*total_solved//total_space:>5}%  {', '.join(ties) or '—'}")

print()
for f in hard_flags:
    print(f"FLAG: {f}")
for r in review:
    print(f"review: {r}")
if not hard_flags and not review:
    print("audit clean — ramps sane, nothing guessable, no opener prereqs")
sys.exit(1 if hard_flags else 0)
