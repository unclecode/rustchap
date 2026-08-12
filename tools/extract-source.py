#!/usr/bin/env python3
"""Pull the teaching points out of a Comprehensive Rust segment so a deck can be
authored with the source material in view rather than from memory.

Their markdown has three useful layers, and the third is the valuable one:

  - the student-facing prose (short, and the voice we copy)
  - `rust,editable` code samples (Apache-2.0)
  - a <details> block of INSTRUCTOR NOTES holding the "why", the common
    misconceptions, and what to demo. This is where puzzle ideas come from:
    a note saying "show what happens if you add a semicolon" is a puzzle.

Writes to bank/extracted/<segment>.md (gitignored). Reading material only —
prose is always rewritten, never copied. See docs/context/foundation/
curriculum.md for the licence terms and the attribution rule.

    python3 tools/extract-source.py control-flow-basics
    python3 tools/extract-source.py --list
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "bank/sources/comprehensive-rust/src")
OUT = os.path.join(ROOT, "bank/extracted")


def strip_boilerplate(text: str) -> str:
    text = re.sub(r"^---\n.*?\n---\n", "", text, flags=re.S)          # frontmatter
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)                # licence headers
    text = re.sub(r"^# // Copyright.*$\n?", "", text, flags=re.M)     # in-snippet notices
    text = re.sub(r"^# // SPDX.*$\n?", "", text, flags=re.M)
    text = re.sub(r"^#\s*$\n?", "", text, flags=re.M)
    return text.strip()


def parse(path: str) -> dict:
    raw = strip_boilerplate(open(path).read())
    notes = re.findall(r"<details>(.*?)</details>", raw, flags=re.S)
    body = re.sub(r"<details>.*?</details>", "", raw, flags=re.S)
    code = re.findall(r"```rust[^\n]*\n(.*?)```", body, flags=re.S)
    prose = re.sub(r"```.*?```", "", body, flags=re.S)
    prose = "\n".join(l for l in prose.split("\n") if l.strip())
    return {"prose": prose.strip(),
            "code": [c.strip() for c in code],
            "notes": "\n".join(n.strip() for n in notes)}


def main() -> int:
    if not os.path.isdir(SRC):
        print("Comprehensive Rust not cloned. Run:\n"
              "  git clone --depth 1 https://github.com/google/comprehensive-rust.git "
              "bank/sources/comprehensive-rust")
        return 1

    if len(sys.argv) < 2 or sys.argv[1] == "--list":
        print("segments:")
        for d in sorted(os.listdir(SRC)):
            if os.path.isdir(os.path.join(SRC, d)):
                n = len([f for f in os.listdir(os.path.join(SRC, d)) if f.endswith(".md")])
                print(f"  {d:34} {n} files")
        return 0

    segment = sys.argv[1].strip("/")
    target = os.path.join(SRC, segment)
    files = []
    if os.path.isdir(target):
        files = [os.path.join(target, f) for f in sorted(os.listdir(target))
                 if f.endswith(".md")]
    elif os.path.exists(target + ".md"):
        files = [target + ".md"]
    else:
        print(f"no such segment: {segment} (try --list)")
        return 1

    os.makedirs(OUT, exist_ok=True)
    out = [f"# Extracted: {segment}",
           "",
           "Source: google/comprehensive-rust (prose CC-BY-4.0, code Apache-2.0).",
           "Reading material for authoring. Rewrite in the RustChap voice; never copy.",
           ""]
    for f in files:
        p = parse(f)
        if not (p["prose"] or p["code"]):
            continue
        out += [f"\n## {os.path.basename(f)[:-3]}", ""]
        if p["prose"]:
            out += ["### what the student reads", "", p["prose"], ""]
        for c in p["code"]:
            out += ["```rust", c, "```", ""]
        if p["notes"]:
            out += ["### instructor notes (puzzle ideas live here)", "", p["notes"], ""]

    dest = os.path.join(OUT, segment.replace("/", "__") + ".md")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "w").write("\n".join(out))
    words = len("\n".join(out).split())
    print(f"{dest}\n  {len(files)} files, {words} words")
    return 0


if __name__ == "__main__":
    sys.exit(main())
