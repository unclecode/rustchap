"""Enums & Matching — Foundations deck 5.

The second half of the old `structs-and-enums` split out. The key sequencing
change: `match` is already taught in the Control Flow deck, which now comes
earlier, so this deck's second lecture BUILDS on it rather than introducing it
cold. That was the user's actual complaint on 2026-08-07.

Comprehensive Rust does the same thing: `match` appears on Day 1 under Control
Flow Basics (plain values), and destructuring enums is a separate Day 2 session.

Source: comprehensive-rust Day 1 PM (User-Defined Types: Enums) and Day 2 AM
(Pattern Matching: Destructuring Enums).
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from authoring import (SOURCES, code, concept, lesson, minimal_edit, prose,
                       reuse, slot, write_deck)

CR = SOURCES["comprehensive-rust"]

write_deck("enums-and-matching", [
    lesson(
        "001", "One of Several",
        "A value that is exactly one of a few named options.",
        ["enums-basics"],
        [prose("An enum declares a type whose value is exactly one of a few named "
               "options, called variants. Most languages have something like this, "
               "usually as a list of constants."),
         code("enum Direction {\n    North,\n    South,\n    East,\n    West,\n}\n\n"
              "let heading = Direction::North;",
              "Four variants, and heading is exactly one of them."),
         prose("Rust adds something those constant lists do not have. A variant can "
               "carry data, and each variant can carry something different."),
         code("enum Command {\n    Add(i32),\n    SetName(String),\n    Reset,\n}",
              "Add carries a number, SetName carries text, Reset carries nothing."),
         prose("This is why enums do so much work in Rust. `Option` and `Result`, which "
               "you meet later, are just enums whose variants carry the value or the "
               "error."),
         prose("Because the type lists every possibility, the compiler knows them all. "
               "That becomes useful the moment you read the value back, which is the "
               "next lecture.")],
        source=CR("Day 1 Afternoon: User-Defined Types")),

    reuse("structs-and-enums.005", "002",
          goal="The traffic light needs three states. The enum only lists two.",
          hints=["Look at what advance() returns for each case.",
                 "Variants are separated by commas."],
          explanation="The function cycles through three states, so the enum has to "
                      "declare all three. Listing only two leaves a case the function "
                      "names but the type does not have, which the compiler rejects. "
                      "This is the everyday shape of an enum. The type states "
                      "every possibility up front."),

    minimal_edit(
        "003", "Carry the Data",
        "The click needs to remember which button. Give the variant somewhere to put it.",
        ["enums-basics"], 1,
        "#[derive(Debug, PartialEq)]\n"
        "enum Event {\n"
        "    Click⟦payload⟧,\n"
        "    Close,\n"
        "}\n\n"
        "fn describe(e: Event) -> String {\n"
        "    match e {\n"
        "        Event::Click(n) => format!(\"click {n}\"),\n"
        "        Event::Close => String::from(\"close\"),\n"
        "    }\n"
        "}\n\n"
        "fn main() {\n"
        "    println!(\"{}\", describe(Event::Click(3)));\n"
        "}\n",
        [slot("payload", "what Click carries", ["(i32)", "", ": i32"], original="")],
        ["#[test]\nfn describes() {\n"
         "    assert_eq!(describe(Event::Click(3)), \"click 3\");\n"
         "    assert_eq!(describe(Event::Close), \"close\");\n}"],
        ["Look at how the match arm reads the click.",
         "A variant carries its data in brackets, like a function's parameters."],
        "`Click(i32)` gives the variant one piece of data, which the match arm then "
        "binds to `n`. With no brackets at all, `Click` carries nothing and the arm "
        "`Event::Click(n)` has nothing to bind, so the compiler rejects it. The form "
        "`Click: i32` is not enum syntax. A variant either carries nothing, carries "
        "unnamed values in brackets, or carries named fields in braces.",
        source=CR("Day 1 Afternoon: User-Defined Types (Enums)")),

    lesson(
        "004", "Reading an Enum Back",
        "match tells you which variant you have, and hands you its data.",
        ["enums-basics", "match-basics"],
        [prose("You met `match` in the Control Flow deck, where it compared a plain "
               "value against a list of options. On an enum it does one more thing. It "
               "also hands you the data the variant is carrying."),
         code("match cmd {\n"
              "    Command::Add(n) => total + n,\n"
              "    Command::SetName(s) => { name = s; total }\n"
              "    Command::Reset => 0,\n}",
              "n and s are the data, pulled out of the variant."),
         prose("The name inside the brackets is yours to choose. It binds to whatever "
               "that variant is carrying, and it only exists inside that arm."),
         prose("The exhaustiveness rule now earns its keep. A `match` on an enum has to "
               "cover every variant, and the compiler counts them. Miss one and you get "
               "error `E0004` before the code ever runs."),
         prose("That check is worth more than it looks. Add a variant to the enum six "
               "months from now, and every `match` that forgot about it becomes a "
               "compile error instead of a bug in production."),
         prose("You can still write `_` as a catch-all, but on an enum it is usually "
               "the wrong choice. It silences exactly the error you want.")],
        source=CR("Day 2 Morning: Pattern Matching")),

    reuse("structs-and-enums.006", "005",
          goal="Two commands. One carries a number, the other carries nothing.",
          hints=["One arm needs a name for the number it is given.",
                 "What should Reset produce?"],
          explanation="`Command::Add(n)` binds the carried number to `n`, which the arm "
                      "then adds to the total. `Command::Reset` carries nothing, so it "
                      "has no brackets, and it produces zero. Both arms produce an "
                      "`i32`, which they must, because the `match` is the function's "
                      "return value."),
    minimal_edit(
        "006", "Name the Payload",
        "The running state carries a number. The arm has to say so.",
        ["enums-basics"], 2,
        "enum Status {\n"
        "    Idle,\n"
        "    Running(u32),\n"
        "    Done,\n"
        "}\n\n"
        "fn label(s: Status) -> &'static str {\n"
        "    match s {\n"
        "        Status::Idle => \"idle\",\n"
        "        ⟦arm⟧ => \"running\",\n"
        "        Status::Done => \"done\",\n"
        "    }\n"
        "}\n\n"
        "fn main() {\n"
        "    println!(\"{}\", label(Status::Running(7)));\n"
        "}\n",
        [slot("arm", "the running arm",
              ["Status::Running(_)", "Status::Running", "Running(_)"],
              original="Status::Running")],
        ["#[test]\nfn labels() {\n"
         "    assert_eq!(label(Status::Idle), \"idle\");\n"
         "    assert_eq!(label(Status::Running(7)), \"running\");\n"
         "    assert_eq!(label(Status::Done), \"done\");\n}"],
        ["`Running` carries a number, so the pattern has to account for it.",
         "You do not need the number here, only a placeholder for it."],
        "`Running` carries a `u32`, so a pattern for it needs brackets. `Running(_)` "
        "says there is a value and you are ignoring it. Writing bare `Status::Running` "
        "treats a data-carrying variant as if it carried nothing, which the compiler "
        "rejects. Writing `Running(_)` without the type name only works after a `use` "
        "brings the variants into scope.",
        source=CR("Day 2 Morning: Pattern Matching (Destructuring Enums)")),

    minimal_edit(
        "007", "Just One Case",
        "Only one variant matters here. Write it without a full match.",
        ["enums-basics", "match-basics"], 2,
        "enum Event {\n"
        "    Click(i32),\n"
        "    Close,\n"
        "}\n\n"
        "fn button(e: Event) -> i32 {\n"
        "    ⟦kw⟧ Event::Click(n) = e {\n"
        "        n\n"
        "    } else {\n"
        "        0\n"
        "    }\n"
        "}\n\n"
        "fn main() {\n"
        "    println!(\"{}\", button(Event::Click(2)));\n"
        "}\n",
        [slot("kw", "the keyword", ["if let", "let", "match"], original="let")],
        ["#[test]\nfn buttons() {\n"
         "    assert_eq!(button(Event::Click(2)), 2);\n"
         "    assert_eq!(button(Event::Close), 0);\n}"],
        ["A plain `let` has to match every time, and this pattern cannot.",
         "There is a form of `let` that is allowed to fail."],
        "`if let` runs the block when the pattern matches and takes the `else` branch "
        "when it does not, so it is the short form of a `match` with one interesting "
        "arm. A plain `let` must always match, and `Event::Click(n)` does not match a "
        "`Close`, so the compiler rejects it as a refutable pattern. `match` needs its "
        "own arm syntax and does not fit this shape. Reach for `if let` when one "
        "variant matters and the rest do not.",
        source=CR("Day 2 Morning: Pattern Matching (Let Control Flow)")),

], concepts=[
    concept("enums-basics", "Enums", "Data shapes",
            "An enum is a type whose value is exactly one of a few named variants.",
            ["An enum declares a type whose value is exactly one of a few named "
             "variants. Most languages have a version of this as a list of constants.",
             "Rust goes further. A variant can carry data, and each variant can carry "
             "something different. `Option` and `Result` are ordinary enums built this "
             "way, which is why they feel so natural in Rust.",
             "You read an enum back with `match`, which tells you which variant you have "
             "and binds whatever it carries. The match must cover every variant, and "
             "missing one is error `E0004`. That check is what turns a new variant into "
             "a compile error rather than a bug found in production."],
            "enum Command {\n    Add(i32),\n    Reset,\n}\n\n"
            "match cmd {\n    Command::Add(n) => total + n,\n"
            "    Command::Reset => 0,\n}",
            "n binds to the number Add is carrying."),
])
