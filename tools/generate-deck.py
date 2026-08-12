#!/usr/bin/env python3
"""Author a deck with an LLM, with the compiler in the loop.

The model drafts, the linter judges, and failures go back to the model for
repair. Nothing reaches content/ until every puzzle has exactly one solution.
This is the project's standing rule made mechanical: LLMs generate variants,
distractors, hints and explanations, but never decide correctness.

    python3 tools/generate-deck.py modules-and-visibility
    python3 tools/generate-deck.py collections --rounds 4
    python3 tools/generate-deck.py --batch drop-and-cleanup testing --jobs 2
    python3 tools/generate-deck.py modules-and-visibility --dry-run

Model comparison on 2026-08-07 (same prompt, same deck): gemini-3.6-flash beat
gemini-3.1-pro-preview and gpt-5.6-sol on verified-puzzle rate at a quarter to an
eighth of the cost. Flash is the default for a measured reason.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from authoring import (best_solution, block_arrangement, code, lesson,  # noqa: E402
                       minimal_edit, prose, slot, slot_selection)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = "gemini-3.6-flash"

# The style checker is the same one CI runs, imported rather than reimplemented
# so the generator cannot drift from the rule it is being held to.
import importlib.util as _ilu  # noqa: E402
_spec = _ilu.spec_from_file_location("checkstyle", f"{ROOT}/tools/check-style.py")
_style = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_style)


def prose_problems(n: dict) -> list[str]:
    """Voice violations in a node's prose, phrased as repair instructions."""
    texts = [n.get("goal", ""), n.get("explanation", "")] + n.get("hints", [])
    for sec in n.get("sections", []):
        if sec.get("kind") == "prose":
            texts.append(sec.get("text", ""))
    found = []
    for t in texts:
        for sent in _style.sentences(t):
            for codeword in _style.check_sentence(sent):
                found.append(f'{codeword} in: "{sent[:90]}"')
    if n.get("type") == "lesson":
        words = sum(len(s.get("text", "").split())
                    for s in n.get("sections", []) if s.get("kind") == "prose")
        if words > _style.MAX_LECTURE_WORDS:
            found.append(f"lecture is {words} words, maximum is {_style.MAX_LECTURE_WORDS}")
    return found
WORK = "/tmp/rustchap-gen"


# ------------------------------------------------------------------ plumbing
def env(name: str) -> str:
    for line in open(f"{ROOT}/.env"):
        m = re.match(r"^\s*([A-Z_]+)\s*=\s*(.*)$", line)
        if m and m.group(1) == name:
            return m.group(2).strip().strip('"').strip("'")
    raise SystemExit(f"{name} missing from .env")


def parse_loose(text: str) -> dict:
    """Models sometimes emit several JSON objects back to back, or wrap the
    object in a fence. Take every complete object and merge their list keys."""
    text = re.sub(r"^\s*```(?:json)?|```\s*$", "", text.strip())
    dec, merged, pos = json.JSONDecoder(), {}, 0
    while pos < len(text):
        try:
            obj, end = dec.raw_decode(text, pos)
        except json.JSONDecodeError:
            nxt = text.find("{", pos + 1)
            if nxt == -1:
                break
            pos = nxt
            continue
        if isinstance(obj, dict):
            for k, v in obj.items():
                if isinstance(v, list):
                    merged.setdefault(k, []).extend(v)
                else:
                    merged.setdefault(k, v)
        pos = end
        while pos < len(text) and text[pos] in " \n\r\t,":
            pos += 1
    if not merged:
        raise ValueError(f"no JSON object found in {len(text)} chars")
    return merged


def ask(prompt: str, model: str) -> tuple[dict, dict]:
    body = {"contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.4, "topP": 0.95,
                                 "responseMimeType": "application/json",
                                 "maxOutputTokens": 60000}}
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=json.dumps(body).encode(),
        headers={"x-goog-api-key": env("GEMINI_API_KEY"),
                 "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=240))
            cand = r["candidates"][0]
            if cand.get("finishReason") not in (None, "STOP"):
                raise RuntimeError(
                    f"model stopped early ({cand['finishReason']}) - the deck is "
                    "too large for one response, ask for fewer nodes")
            text = "".join(p.get("text", "") for p in cand["content"]["parts"])
            out = parse_loose(text)
            if "nodes" not in out:
                raise RuntimeError(
                    "response had no 'nodes' key - probably truncated mid-object; "
                    f"salvaged keys were {sorted(out)[:6]}")
            return out, r.get("usageMetadata", {})
        except (urllib.error.HTTPError, urllib.error.URLError) as e:
            if attempt == 2:
                raise
            time.sleep(5 * (attempt + 1))
    raise SystemExit("unreachable")


# ------------------------------------------------------------------- prompt
def curriculum_map() -> str:
    """Every deck and what it owns. Without this the model teaches Option in a
    collections deck and trait bounds in Foundations, because it cannot see who
    else covers what. Measured on 2026-08-07: all three models drifted."""
    m = json.load(open(f"{ROOT}/content/curriculum.json"))
    lv = {x["id"]: x["title"] for x in m["levels"]}
    out, cur = [], None
    for d in m["decks"]:
        if lv[d["level"]] != cur:
            cur = lv[d["level"]]
            out.append(f"\n{cur}:")
        out.append(f"  - {d['title']}")
    return "\n".join(out)


def build_prompt(deck: str, want: int, segments: list[str]) -> str:
    system = open(f"{ROOT}/tools/prompts/deck-author.md").read()

    context = []
    for seg in segments:
        path = f"{ROOT}/bank/extracted/{seg.replace('/', '__')}.md"
        if not os.path.exists(path):
            subprocess.run([sys.executable, f"{ROOT}/tools/extract-source.py", seg],
                           cwd=ROOT, capture_output=True)
        if os.path.exists(path):
            context.append(open(path).read())
    ctx = "\n\n".join(context)[:24000] or "(no extract available; use your own knowledge)"

    pack = json.load(open(f"{ROOT}/content/packs/{deck}/pack.json"))
    current = [json.load(open(f"{ROOT}/content/packs/{deck}/puzzles/{p}.json"))
               for p in pack["order"]]

    def sample(path):
        n = json.load(open(f"{ROOT}/content/packs/{path}.json"))
        return {k: n[k] for k in ("title", "goal", "concepts", "difficulty",
                                  "template", "interaction", "evaluation", "hints",
                                  "explanation", "scoring") if k in n}
    examples = {
        "a_good_lecture": sample("control-flow/puzzles/control-flow.005"),
        "a_good_minimal_edit": sample("enums-and-matching/puzzles/enums-and-matching.007"),
        "a_good_best_solution": sample("build-the-iterator/puzzles/build-the-iterator.005"),
        "a_good_block_arrangement": sample("build-the-iterator/puzzles/build-the-iterator.001"),
    }
    concepts = sorted(f[:-5] for f in os.listdir(f"{ROOT}/content/concepts")
                      if f.endswith(".json") and f != "topics.json")
    topics = json.load(open(f"{ROOT}/content/concepts/topics.json"))["topics"]

    existing = (json.dumps(current, indent=1, ensure_ascii=False)[:12000]
                if current else "(this deck is empty, you are writing all of it)")

    return f"""{system}

---

<context>
Source material from google/comprehensive-rust. Rewrite in the RustChap voice.
Never copy the prose. The "instructor notes" sections name what students
actually get wrong, which is where the best puzzles come from.

{ctx}
</context>

<examples>
Real RustChap nodes, one per interaction type. Match this shape and this
quality. Note how every distractor fails for a Rust reason, how each explanation
names why each wrong choice is wrong, and how hints narrow without answering.

{json.dumps(examples, indent=1, ensure_ascii=False)[:14000]}
</examples>

<curriculum_map>
The whole course, in order. You are writing "{pack['title']}".
{curriculum_map()}

SCOPE IS A HARD RULE, not a suggestion. A concept belongs to exactly one deck.

- You MAY USE another deck's concept when the code needs it. Reading a `HashMap`
  hands you an `Option`, and that is unavoidable.
- You MAY NOT TEACH it. No lecture may be built around another deck's concept,
  and no lecture title may name one.
- When you must use one, say in a single sentence where it is properly covered,
  then move on. "Reading a map hands back an `Option`. The Option & Result deck
  covers what that is."

Test yourself on every lecture: if its title or its main idea belongs to a deck
listed above other than "{pack['title']}", delete it and write a different one.
A lecture called "Safe Indexing and Options" inside a collections deck is exactly
the mistake this rule exists to prevent, and it has been made three times.
</curriculum_map>

<current_content>
"{pack['title']}" — {pack['description']}
It currently has {len(current)} nodes. They STAY and are not in your output. Do
not repeat their titles, their failure modes, or their teaching points.

{existing}
</current_content>

<allowed_concepts>
{', '.join(concepts)}
</allowed_concepts>

<allowed_topics>
{', '.join(topics)}
</allowed_topics>

<task>
Write {want} NEW nodes for "{pack['title']}", plus any new concepts they need and
2 to 4 review cards per concept taught. Interleave lectures so each is followed
by puzzles that drill it. Output only the JSON object from OUTPUT FORMAT.
</task>"""


# ---------------------------------------------------------------- conversion
SRC = lambda where: {"origin": "comprehensive-rust", "license": "CC-BY-4.0",
                     "attribution": f"adapted from {where}"}


def to_node(n: dict, num: str):
    """One model node -> one RustChap node. Tolerates the shape drift models
    produce (choices as objects, tests nested under evaluation)."""
    t = n["type"]
    src = SRC(n.get("source", "comprehensive-rust"))
    tests = n.get("tests") or n.get("evaluation", {}).get("tests", [])
    ch = lambda s: [c["text"] if isinstance(c, dict) else c for c in s["choices"]]

    if t == "lesson":
        secs = [prose(s["text"]) if s["kind"] == "prose" else code(s["code"], s["caption"])
                for s in n["sections"]]
        return lesson(num, n["title"], n["goal"], n["concepts"], secs, source=src)

    common = (num, n["title"], n["goal"], n["concepts"], n.get("difficulty", 2))
    if t in ("minimal-edit", "slot-selection"):
        sl = [slot(s["id"], s.get("label", s["id"]), ch(s), original=s.get("original"))
              for s in n["slots"]]
        if t == "minimal-edit":
            return minimal_edit(*common, n["template"], sl, tests, n["hints"],
                                n["explanation"], source=src)
        return slot_selection(*common, n["template"], sl, tests, n["hints"],
                              n["explanation"], source=src, primary="token_edits",
                              fluent={"token_edits": len(sl)},
                              optimal={"token_edits": len(sl)})

    m = n.get("metric") or {"primary": "clone_count", "fluent": 1, "optimal": 0}
    mk = dict(primary=m["primary"], fluent={m["primary"]: m["fluent"]},
              optimal={m["primary"]: m["optimal"]})
    if t == "best-solution":
        cands = [(c["id"], c["code"]) for c in n["candidates"]]
        return best_solution(*common, cands, tests, n["hints"], n["explanation"],
                             source=src, **mk)
    if t == "block-arrangement":
        it = n.get("interaction", n)
        blocks = [(b["id"], b["text"]) for b in it["blocks"]]
        return block_arrangement(*common, it["fixed_prefix"], blocks,
                                 it["fixed_suffix"], tests, n["hints"],
                                 n["explanation"], source=src, **mk)
    raise ValueError(f"unknown interaction type {t!r}")


# ----------------------------------------------------------------- verifying
def verify(deck: str, data: dict, offset: int,
           only: set | None = None) -> tuple[dict, list[str]]:
    """Compile submissions in a scratch pack. Returns per-node problems.

    `only` restricts compilation to those node indices. Repair rounds change one
    or two nodes, and the linter has no cache, so recompiling the whole deck
    every round was doing ~18x the necessary work on an 18-node deck.
    """
    work = f"{WORK}/{deck}"
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(f"{work}/pack/puzzles")
    conc = f"{work}/concepts"
    shutil.copytree(f"{ROOT}/content/concepts", conc)
    for c in data.get("new_concepts", []):
        c["schema_version"] = 1
        json.dump(c, open(f"{conc}/{c['id']}.json", "w"), indent=2, ensure_ascii=False)

    index, fatal = {}, []
    for i, n in enumerate(data["nodes"]):
        if only is not None and i not in only:
            continue
        try:
            node = to_node(n, f"{offset + i + 1:03d}")
        except Exception as e:
            fatal.append(f"node {i} ({n.get('title','?')}): malformed - {type(e).__name__} {e}")
            continue
        node["id"] = f"gen.{node['id'].split('.')[-1]}"
        node["track"] = "gen"
        index[node["id"]] = i
        json.dump(node, open(f"{work}/pack/puzzles/{node['id']}.json", "w"),
                  indent=2, ensure_ascii=False)

    order = sorted(index)
    json.dump({"schema_version": 1, "id": "gen", "title": "gen", "description": "scratch",
               "toolchain": "1.97.1", "order": order, "icon": "circle",
               "accent": "gray", "level": "foundations"},
              open(f"{work}/pack/pack.json", "w"), indent=2)

    out = subprocess.run(
        ["cargo", "run", "-q", "-p", "puzzle-linter", "--release", "--",
         "--summary", "--concepts", conc, f"{work}/pack/"],
        cwd=ROOT, capture_output=True, text=True).stdout

    problems: dict[int, list[str]] = {}
    for line in out.splitlines():
        m = re.search(r"(gen\.\d+): (\d+) submissions? — (\d+) solved", line)
        if m and m.group(1) in index:
            solved = int(m.group(3))
            if solved == 0:
                problems.setdefault(index[m.group(1)], []).append(
                    "NO combination of your choices compiles and passes the tests. "
                    "At least one must. Check that the correct choice really is "
                    "valid Rust and that your tests match what the code returns.")
            elif solved > 1:
                problems.setdefault(index[m.group(1)], []).append(
                    f"{solved} different combinations pass, so the puzzle has no "
                    "single answer. Make the distractors genuinely wrong: each must "
                    "fail to compile or fail a test.")
        m = re.search(r"ERROR: (gen\.\d+): (.+)", line)
        if m and m.group(1) in index:
            problems.setdefault(index[m.group(1)], []).append(m.group(2))

    # Card problems are reported against the deck as a whole (index -1 is not a
    # node), so collect them separately and attach to the first node.
    bad_cards = []
    for c in (data.get("review_cards", []) if only is None else []):
        q = c.get("prompt", "").strip()
        if re.match(r"^(are|do|does|is|can|will|should|did|has|have)\b", q, re.I):
            bad_cards.append(f'card {c.get("id")} is a yes/no question: "{q[:70]}". '
                             "Ask what, why, how, or when instead.")
        if len(c.get("answer", "").split()) < 12:
            bad_cards.append(f'card {c.get("id")} answer is too short to teach '
                             "anything. Two or three real sentences.")
        # The PROMPT is prose too. Checking only the answer let unbackticked
        # code and semicolons through in 7 cards on 2026-08-07.
        for field in ("prompt", "answer"):
            for sent in _style.sentences(c.get(field, "")):
                for codeword in _style.check_sentence(sent):
                    bad_cards.append(
                        f'card {c.get("id")} {field}: {codeword} in "{sent[:70]}"')
        t = c.get("title", "")
        if not (3 <= len(t) <= 44):
            bad_cards.append(f'card {c.get("id")} title is {len(t)} chars, '
                             "the schema allows 3 to 44")
    if bad_cards:
        problems.setdefault(0, []).extend(
            ["REVIEW CARDS (return the whole corrected review_cards list): " + b
             for b in bad_cards])

    for i, n in enumerate(data["nodes"]):
        if only is not None and i not in only:
            continue
        for issue in prose_problems(n):
            problems.setdefault(i, []).append(
                f"VOICE: {issue}. Rewrite as short declarative sentences, one idea "
                "each, no semicolons joining clauses, no rhetorical colons, no em "
                "dashes, nothing over 30 words.")
    return problems, fatal


def repair_prompt(deck: str, data: dict, problems: dict, fatal: list) -> str:
    broken = [{"index": i, "node": data["nodes"][i], "problems": p}
              for i, p in sorted(problems.items())]
    return f"""You wrote nodes for the RustChap deck "{deck}". The compiler ran
every combination of every puzzle. These nodes FAILED and must be rewritten.

{json.dumps(broken, indent=1, ensure_ascii=False)[:30000]}

{("Also malformed: " + "; ".join(fatal)) if fatal else ""}

Rewrite ONLY these nodes, keeping each one's teaching intent, title and
misconception. The rules that matter most here:

- Exactly ONE combination of choices may compile AND pass every test.
- Every other combination must fail for a reason a learner benefits from.
- Verify mentally, choice by choice: does this compile? does it pass the tests?
- Keep templates under 16 lines, and keep 2 slots with 3 choices each.
- For best-solution, exactly one candidate may reach the optimal metric value.
- For block-arrangement, at most 5 blocks, and the given order must compile.

Return JSON: {{"nodes": [{{"index": <the same index>, "node": {{...full node...}}}}]}}

If any problem above is prefixed REVIEW CARDS, also return the complete
corrected list as {{"review_cards": [...]}} alongside "nodes".
"""


# -------------------------------------------------------------------- commit
def commit(deck: str, data: dict, offset: int, skip_lint: bool = False) -> dict:
    pack_dir = f"{ROOT}/content/packs/{deck}"
    pack = json.load(open(f"{pack_dir}/pack.json"))
    # NEVER trust the caller's offset: it comes from content/curriculum.json,
    # which goes stale as soon as a deck is generated. Numbering from a stale
    # count overwrites existing puzzles and duplicates their ids, which crashes
    # the app on a duplicate dictionary key. Number from what is actually there.
    used = {int(pid.rsplit(".", 1)[1]) for pid in pack["order"]} or {0}
    offset = max(used)
    written = []
    for i, n in enumerate(data["nodes"]):
        node = to_node(n, f"{offset + i + 1:03d}")
        node["id"] = f"{deck}.{node['id'].split('.')[-1]}"
        node["track"] = deck
        os.makedirs(f"{pack_dir}/puzzles", exist_ok=True)
        json.dump(node, open(f"{pack_dir}/puzzles/{node['id']}.json", "w"),
                  indent=2, ensure_ascii=False)
        open(f"{pack_dir}/puzzles/{node['id']}.json", "a").write("\n")
        written.append(node["id"])
    pack["order"] = pack["order"] + written
    json.dump(pack, open(f"{pack_dir}/pack.json", "w"), indent=2, ensure_ascii=False)
    open(f"{pack_dir}/pack.json", "a").write("\n")

    for c in data.get("new_concepts", []):
        c["schema_version"] = 1
        p = f"{ROOT}/content/concepts/{c['id']}.json"
        json.dump(c, open(p, "w"), indent=2, ensure_ascii=False)
        open(p, "a").write("\n")
    REQUIRED = ("id", "kind", "title", "concepts", "prompt", "answer")
    for c in data.get("review_cards", []):
        if "prompt" not in c and "question" in c:      # common model slip
            c["prompt"] = c.pop("question")
        if any(k not in c for k in REQUIRED):
            continue                                    # never write a broken card
        c["schema_version"] = 1
        p = f"{ROOT}/content/review/{c['id']}.json"
        json.dump(c, open(p, "w"), indent=2, ensure_ascii=False)
        open(p, "a").write("\n")
    # Verification happened in a scratch pack under a different id, so the real
    # deck has no outcomes yet. Without them the app has nothing to score
    # against and the progression audit fails on a missing file.
    if not skip_lint:
        subprocess.run(
            ["cargo", "run", "-q", "-p", "puzzle-linter", "--release", "--",
             "--concepts", f"{ROOT}/content/concepts", f"{pack_dir}/"],
            cwd=ROOT, capture_output=True, text=True)

    return {"nodes": written,
            "concepts": [c["id"] for c in data.get("new_concepts", [])],
            "cards": [c["id"] for c in data.get("review_cards", [])]}


# ---------------------------------------------------------------------- main
def generate(deck: str, rounds: int, dry: bool, model: str, chunk: int = 6) -> dict:
    man = json.load(open(f"{ROOT}/content/curriculum.json"))
    entry = next((d for d in man["decks"] if d["id"] == deck), None)
    if not entry:
        return {"deck": deck, "error": "not in content/curriculum.json"}
    want = max(0, entry["target"] - entry["nodes"])
    if want == 0:
        return {"deck": deck, "error": "already at target"}

    say = lambda m: print(f"  {m}", flush=True)
    log = [f"[{deck}] need {want} nodes (have {entry['nodes']}, target {entry['target']})"]

    # One response cannot hold a big deck: the three 12-14 node decks in the
    # 2026-08-07 batch all truncated. Ask in chunks of at most 7, feeding the
    # earlier chunk back so the ramp continues and nothing is duplicated.
    CHUNK = chunk
    chunks, left = [], want
    while left > 0:
        chunks.append(min(CHUNK, left))
        left -= CHUNK
    data, spent = {"nodes": [], "new_concepts": [], "review_cards": []}, []
    for ci, n_this in enumerate(chunks):
        prompt = build_prompt(deck, n_this, entry["source_segments"])
        if ci:
            prompt += (f"\n\n<already_written>\nYou have already written these "
                       f"{len(data['nodes'])} nodes for this same deck. Continue the "
                       f"sequence and the difficulty ramp. Do not repeat their "
                       f"titles, failure modes, or misconceptions, and do not "
                       f"redefine concepts you already defined.\n\n"
                       + json.dumps([{"title": x["title"],
                                      "misconception": x.get("misconception"),
                                      "concepts": x["concepts"]}
                                     for x in data["nodes"]], indent=1)
                       + "\n</already_written>")
        try:
            part, usage = ask(prompt, model)
            spent.append(usage)
        except RuntimeError as e:
            # A chunk heavy in best-solution nodes (three full programs each)
            # can still overrun the output budget. Halve the ask and retry
            # rather than losing the whole deck.
            if "truncated" not in str(e) and "stopped early" not in str(e):
                raise
            say(f"[{deck}] chunk overran the output budget, splitting it")
            part = {"nodes": [], "new_concepts": [], "review_cards": []}
            half = max(1, n_this // 2)
            for sub in (half, n_this - half):
                if sub <= 0:
                    continue
                sub_prompt = build_prompt(deck, sub, entry["source_segments"])
                already = data["nodes"] + part["nodes"]
                if already:
                    sub_prompt += ("\n\n<already_written>\nAlready written for this "
                                   "deck. Continue the ramp, repeat nothing.\n"
                                   + json.dumps([{"title": x["title"],
                                                  "concepts": x["concepts"]}
                                                 for x in already], indent=1)
                                   + "\n</already_written>")
                sp, su = ask(sub_prompt, model)
                spent.append(su)
                part["nodes"] += sp.get("nodes", [])
                part["new_concepts"] += sp.get("new_concepts", [])
                part["review_cards"] += sp.get("review_cards", [])
        data["nodes"] += part.get("nodes", [])
        seen = {c["id"] for c in data["new_concepts"]}
        data["new_concepts"] += [c for c in part.get("new_concepts", [])
                                 if c["id"] not in seen]
        cseen = {c["id"] for c in data["review_cards"]}
        data["review_cards"] += [c for c in part.get("review_cards", [])
                                 if c["id"] not in cseen]
    say(f"[{deck}] drafted {len(data['nodes'])} nodes")
    log.append(f"[{deck}] drafted {len(data['nodes'])} nodes in {len(chunks)} chunk(s), "
               f"{len(data['new_concepts'])} concepts, "
               f"{len(data['review_cards'])} cards")

    if rounds == 0:
        # --no-verify: draft only. Everything is compiled in one pass at the end
        # instead of per deck, which is far faster when generating many decks.
        tin = sum(u.get("promptTokenCount", 0) for u in spent)
        tout = sum(u.get("candidatesTokenCount", 0) for u in spent)
        result = {"deck": deck, "log": log, "cost": round((tin*0.5+tout*3)/1e6, 4),
                  "nodes": len(data["nodes"])}
        result.update(commit(deck, data, entry["nodes"], skip_lint=True))
        return result

    recheck = None                      # None = verify everything (first pass)
    for rnd in range(1, rounds + 1):
        problems, fatal = verify(deck, data, entry["nodes"], only=recheck)
        if not problems and not fatal:
            log.append(f"[{deck}] round {rnd}: all puzzles verified")
            break
        say(f"[{deck}] round {rnd}: {len(problems)} node(s) failed, repairing")
        log.append(f"[{deck}] round {rnd}: {len(problems)} node(s) failed, repairing")
        if rnd == rounds:
            log.append(f"[{deck}] out of rounds, dropping {len(problems)} bad node(s)")
            keep = [n for i, n in enumerate(data["nodes"]) if i not in problems]
            data["nodes"] = keep
            break
        fix, u = ask(repair_prompt(deck, data, problems, fatal), model)
        spent.append(u)
        repaired = set()
        for item in fix.get("nodes", []):
            i = item.get("index")
            if isinstance(i, int) and 0 <= i < len(data["nodes"]):
                data["nodes"][i] = item["node"]
                repaired.add(i)
        # Next round only needs to look at what actually changed. Anything not
        # repaired already passed and cannot have broken since.
        recheck = repaired or set(problems)
        if fix.get("review_cards"):
            # Merge by id. Replacing the list wholesale loses every card the
            # repair did not happen to resend (structs kept 1 of 13 this way).
            byid = {c["id"]: c for c in data.get("review_cards", [])}
            for c in fix["review_cards"]:
                byid[c["id"]] = c
            data["review_cards"] = list(byid.values())

    tin = sum(u.get("promptTokenCount", 0) for u in spent)
    tout = sum(u.get("candidatesTokenCount", 0) for u in spent)
    cost = (tin * 0.5 + tout * 3) / 1e6
    result = {"deck": deck, "log": log, "cost": round(cost, 4),
              "nodes": len(data["nodes"])}
    if dry:
        json.dump(data, open(f"/tmp/gen-{deck}.json", "w"), indent=1, ensure_ascii=False)
        result["dry_run"] = f"/tmp/gen-{deck}.json"
    else:
        result.update(commit(deck, data, entry["nodes"]))
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("decks", nargs="*")
    ap.add_argument("--batch", nargs="*", default=None)
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--chunk", type=int, default=6)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    decks = a.batch if a.batch else a.decks
    if not decks:
        return print("usage: generate-deck.py <deck-id> [...] [--jobs N]") or 1

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = {ex.submit(generate, d, a.rounds, a.dry_run, a.model, a.chunk): d for d in decks}
        for f in concurrent.futures.as_completed(futs):
            try:
                results.append(f.result())
            except Exception as e:
                results.append({"deck": futs[f], "error": f"{type(e).__name__}: {e}"})

    total = 0.0
    for r in sorted(results, key=lambda x: x["deck"]):
        print()
        for line in r.get("log", []):
            print(" ", line, flush=True)
        if r.get("error"):
            print(f"  [{r['deck']}] ERROR: {r['error']}")
            continue
        total += r.get("cost", 0)
        if r.get("dry_run"):
            print(f"  [{r['deck']}] dry run -> {r['dry_run']}")
        else:
            print(f"  [{r['deck']}] committed {len(r['nodes'])} nodes, "
                  f"{len(r['concepts'])} concepts, {len(r['cards'])} cards")
    print(f"\ntotal cost: ${total:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
