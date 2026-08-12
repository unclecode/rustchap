#!/usr/bin/env python3
"""Enforce the RustChap writing voice on lecture prose, concept lectures, and
review-card answers.

The style rule used to live only in the author's head, and on 2026-08-07 it
failed: a scan found 50 semicolon-welded clauses, 112 rhetorical colons, and
sentences up to 45 words. The model is now google/comprehensive-rust — short
declarative sentences, one idea each, anchored to the language the reader
already knows.

Existing prose predates the rule, so this runs against a BASELINE: CI fails on
new violations only. As decks get rewritten the baseline shrinks. Regenerate it
with --update-baseline after a rewrite, and the count should never go up.

    python3 tools/check-style.py                  # check against baseline
    python3 tools/check-style.py --report         # every violation, grouped
    python3 tools/check-style.py --update-baseline
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "tools/style-baseline.json")

MAX_SENTENCE_WORDS = 30
MAX_LECTURE_WORDS = 200

# A colon that introduces a list is fine ("three keywords: while, loop, and for").
# A colon welding two clauses is the rhetorical habit we are killing.
LIST_COLON = re.compile(r":\s*(?:[`\w][^.]*,|\s*$)")


def sentences(text: str) -> list[str]:
    # Don't split on the dot inside `1..5`, `self.name`, or "e.g."
    protected = re.sub(r"(?<=\w)\.(?=\w)", "\x00", text)
    parts = re.split(r"(?<=[.!?])\s+", protected)
    return [p.replace("\x00", ".").strip() for p in parts if p.strip()]


def check_sentence(s: str) -> list[str]:
    """Violation codes for one sentence."""
    found = []
    # Inline code often contains `:` and `;` as Rust syntax (`count: u32`,
    # `let x = 1;`). Mask it before looking for punctuation habits.
    bare = re.sub(r"`[^`]*`", "X", s)
    if "; " in bare:
        found.append("semicolon")
    # colon followed by a clause (starts lowercase, no comma-list after it)
    for m in re.finditer(r"[^\s:]:\s+(?=[a-z`])", bare):
        tail = bare[m.end():]
        if not LIST_COLON.match(":" + tail) and "," not in tail.split(".")[0]:
            found.append("clause-colon")
            break
    if "—" in s or "–" in s:
        found.append("em-dash")
    # Unambiguous Rust punctuation outside backticks means the author wrote code
    # as prose. It reads badly and its semicolons look like sentence punctuation.
    if re.search(r"(::|#\[|->)", bare):
        found.append("bare-code")
    words = len(bare.split())
    if words > MAX_SENTENCE_WORDS:
        found.append("long-sentence")
    return found


def collect() -> list[dict]:
    """Every prose unit in the content tree, with its violations."""
    out = []

    def add(where: str, kind: str, text: str):
        for s in sentences(text):
            for code in check_sentence(s):
                out.append({"where": where, "kind": kind, "code": code,
                            "text": s[:120]})

    for f in sorted(glob.glob(os.path.join(ROOT, "content/packs/*/puzzles/*.json"))):
        p = json.load(open(f))
        pid = p["id"]
        if p["interaction"]["type"] == "lesson":
            total = 0
            for sec in p["interaction"]["sections"]:
                if sec["kind"] == "prose":
                    add(pid, "lecture", sec["text"])
                    total += len(sec["text"].split())
            if total > MAX_LECTURE_WORDS:
                out.append({"where": pid, "kind": "lecture", "code": "long-lecture",
                            "text": f"{total} words (max {MAX_LECTURE_WORDS})"})
        add(pid, "goal", p.get("goal", ""))
        add(pid, "explanation", p.get("explanation", ""))
        for h in p.get("hints", []):
            add(pid, "hint", h)
        if "source" not in p:
            out.append({"where": pid, "kind": "meta", "code": "no-source",
                        "text": "node has no source record"})

    for f in sorted(glob.glob(os.path.join(ROOT, "content/concepts/*.json"))):
        if f.endswith("topics.json"):
            continue
        c = json.load(open(f))
        for para in c["lecture"]:
            add(c["id"], "concept", para)
        add(c["id"], "concept", c["summary"])

    for f in sorted(glob.glob(os.path.join(ROOT, "content/review/*.json"))):
        c = json.load(open(f))
        add(c["id"], "card", c["answer"])
        add(c["id"], "card", c["prompt"])

    return out


def fingerprint(v: dict) -> str:
    return f"{v['where']}|{v['kind']}|{v['code']}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="print every violation")
    ap.add_argument("--update-baseline", action="store_true")
    args = ap.parse_args()

    violations = collect()
    counts = collections.Counter(v["code"] for v in violations)

    if args.report:
        by_code = collections.defaultdict(list)
        for v in violations:
            by_code[v["code"]].append(v)
        for code in sorted(by_code, key=lambda c: -len(by_code[c])):
            print(f"\n=== {code} ({len(by_code[code])}) ===")
            for v in by_code[code][:60]:
                print(f"  [{v['where']}] {v['text']}")
        print(f"\nTOTAL {len(violations)}: " +
              ", ".join(f"{k}={v}" for k, v in counts.most_common()))
        return 0

    current = collections.Counter(fingerprint(v) for v in violations)

    if args.update_baseline:
        json.dump({"note": "known style violations in pre-2026-08-07 content; "
                           "this number must only ever go DOWN",
                   "total": len(violations),
                   "by_code": dict(counts),
                   "fingerprints": dict(sorted(current.items()))},
                  open(BASELINE, "w"), indent=2)
        print(f"baseline updated: {len(violations)} known violations")
        return 0

    if not os.path.exists(BASELINE):
        print("no baseline; run --update-baseline first")
        return 1

    base = collections.Counter(json.load(open(BASELINE))["fingerprints"])
    new = [f for f, n in current.items() if n > base.get(f, 0)]

    if new:
        print(f"STYLE: {len(new)} new violation(s) — see docs/context/foundation/"
              "curriculum.md for the rules\n")
        index = {fingerprint(v): v for v in violations}
        for f in sorted(new)[:40]:
            v = index[f]
            print(f"  {v['code']:14} [{v['where']}] {v['text']}")
        return 1

    fixed = sum(base.values()) - sum(current.values())
    msg = f"style: no new violations ({sum(current.values())} known)"
    print(msg + (f", {fixed} fixed since baseline" if fixed > 0 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
