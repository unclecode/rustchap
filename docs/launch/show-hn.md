# Show HN launch kit

Draft for the RustChap Show HN post. Nothing here is published — copy the title
and body into Hacker News by hand.

## When

**Tuesday 18 August, 21:00 Singapore time** (09:00 US Eastern).

US Eastern morning is Singapore evening, so the peak window falls at a
convenient hour:

| US Eastern | Singapore |
| --- | --- |
| 08:00 | 20:00 |
| **09:00** | **21:00** |
| 10:00 | 22:00 |
| 11:00 | 23:00 |

Tuesday to Thursday are the strong days. Avoid Friday: the thread runs into a US
weekend when traffic drops. Ranking is roughly `points / (age + 2)^1.8`, so the
first two hours decide the outcome — **be free to answer comments until 23:00**,
and do not post and go to sleep.

**Never ask for upvotes**, anywhere, including private messages. Hacker News
detects voting rings and the penalty is the post being flagged or the account
banned. Sharing the link neutrally is fine.

## Title

```
Show HN: RustChap – Rust puzzles for iPhone where every answer is precompiled
```

Alternatives:

```
Show HN: RustChap – I precompiled 3,160 Rust answers so a puzzle game works offline
Show HN: Euclidea-style Rust puzzles, with rustc deciding every answer
```

The first states the platform upfront, because discovering "iOS only" in the
comments annoys people, and "precompiled" is the word that makes a technical
reader curious. The second is punchier, but numbers in a title read as marketing
to some. The third is the best of the three if the reader knows Euclidea, and
meaningless if not.

## Body

Post this as the first comment, immediately after submitting.

---

I wanted Rust to be instinct rather than vocabulary — I'm planning to rewrite
Crawl4AI in Rust, and reading the book wasn't getting me there. I've played
Euclidea (the geometry puzzle game) through several times, so I built that shape
of thing for Rust.

Each puzzle is a tiny program with a few tokens replaced by choices. You don't
type: you tap tokens, reorder statements, or pick an implementation. The
interesting constraint is that iOS can't compile Rust — no JIT — so the app can't
evaluate anything at runtime.

So I enumerate every legal combination of every puzzle ahead of time and compile
all of them with real rustc and Clippy on a pinned toolchain, storing the
verdict, the diagnostics, and metrics like clone count. That's 3,160 compiled
submissions across 335 puzzles. The app ships those verdicts and looks yours up
by a canonical hash of your edit operations, computed identically in Rust and
Swift. Tapping Run is a dictionary lookup, so it's instant and works fully
offline, and the verdict is the compiler's rather than my opinion.

This also enforces the design rule: a puzzle is only valid if exactly one
combination is optimal. CI recompiles every submission on every push and fails if
any verdict drifts. It caught a genuine bug last week — rustc names closures by
source location, which includes the temp directory, so three puzzles could never
reproduce their own stored verdicts.

Scoring is mechanical rather than points: Solved means it compiles and passes
tests, Optimal means you matched the budget, like `0C·2E` for zero clones in two
edits. `.clone()` usually compiles and usually scores Solved but not Optimal,
which is the whole point — the goal is reaching for the right thing, not merely a
working thing.

Honest caveats:

- **iPhone only.** I built it for myself, on the thing I carry.
- **TestFlight, not the App Store** — 0.1 has been sitting in "Waiting for
  Review" for 9 days.
- **Source-available, not open source.** Apache-2.0 plus the Commons Clause, so
  you can use, modify and build it, but not sell it or a substantial derivative.
  I know that isn't OSI open source and I'd rather say so plainly than fudge the
  word.
- **Most of the 477 lectures and puzzles were drafted by a model, then judged by
  the compiler.** Anything that produced zero correct answers, or more than one
  optimal answer, was rejected and rewritten automatically. I wrote the
  curriculum structure, the voice rules, and the review pass. Every puzzle was
  written for this format — you can't lift an exercise from elsewhere into a
  fixed answer space that has to enumerate and compile. What each node records is
  where the *idea* came from: 373 follow a topic from Google's Comprehensive Rust
  (CC-BY-4.0), which also shaped the ordering and the house voice; 73 are
  inspired by a rustlings exercise and 6 by an Exercism one (both MIT); 25 are
  mine outright.

Play: https://testflight.apple.com/join/uCRCD2wq
Source: https://github.com/unclecode/rustchap

What I'd most like feedback on: whether the puzzles actually build instinct or
just pattern-matching, and which concepts are missing. Everything is verified but
nothing has been judged by a Rust expert yet.

---

## Why the body is shaped this way

**The technical constraint leads.** "iOS can't compile Rust, so I precompiled
everything" is a real engineering problem with a real solution, and that earns
attention independently of whether the reader wants a Rust game.

**The CI bug is included deliberately.** It demonstrates the verification is
real rather than claimed.

**All four caveats are stated before anyone asks.** The licence and the
model-drafted content would otherwise become the top comment and take the thread
with them.

**It ends with a real question**, which invites the expert replies that are the
actual point of posting.

## The numbers, verified against the repo

| | |
| --- | --- |
| Nodes | 477 across 31 decks, six levels |
| Puzzles / lectures | 335 / 142 |
| Precompiled submissions | 3,160 |
| Review cards / concepts | 528 / 64 |
| Toolchain | pinned, rustc + Clippy |

Source attribution across the 477 nodes:

| Origin | Nodes | Relation recorded |
| --- | --- | --- |
| comprehensive-rust | 373 | *adapted from* a segment (sequence and voice) |
| rustlings | 73 | *inspired by* a named exercise |
| original | 25 | — |
| exercism | 6 | *inspired by* a named exercise |

Do not say "exercises draw on rustlings and Exercism" — it implies the exercises
were ported, which they were not, and it undersells the work.

## Questions to expect, with answers ready

**"This isn't open source."** Correct, and say so first. Apache-2.0 with the
Commons Clause: use, modify, build it for yourself, contribute back, but don't
sell it or a substantial derivative.

**"Why not rustlings?"** rustlings checks whether you *can* fix it. RustChap
scores whether you reached for the *right* fix — `.clone()` compiles and passes
tests, and still doesn't earn Optimal.

**"Android? Web?"** Built it for myself, on the phone I carry. The content, the
schema and the evaluator are all platform-neutral JSON and Rust; only the app is
iOS.

**"AI-generated content?"** Answered in the post before anyone asks. Drafted by a
model, judged by the compiler, rejected and rewritten when the answer space was
wrong.

**"TestFlight is friction."** Fair. The App Store version is stuck in review; the
source builds with Xcode if they'd rather.

## Afterwards

`scratchpad/hn-watch.py` reads the thread through the free Firebase API — score,
comment count, and the full nested tree, printing only what is new since the last
run. There is no write API, so replies have to be typed into the site.
