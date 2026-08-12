"""Structs — Foundations deck 4.

Replaces the first half of the old `structs-and-enums`, whose single lecture
"Shape Your Data" taught structs, impl, &self/self, enums, match and
exhaustiveness in 159 words. The user's report on 2026-08-07 was that it jumped
to `match` with nothing introducing it, and that "a struct names a shape" meant
nothing. Both are fixed here: this deck is structs only, in two lectures that
each teach one thing, and enums moved to their own deck.

The three puzzles are the verified rustlings-derived ones from the old deck,
carried over with `reuse()` — the templates and tests were never the problem.

Source: comprehensive-rust Day 1 PM (User-Defined Types) and Day 2 AM (Methods).
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from authoring import (SOURCES, code, concept, lesson, minimal_edit, prose,
                       reuse, slot, write_deck)

CR = SOURCES["comprehensive-rust"]

write_deck("structs", [
    lesson(
        "001", "Grouping Values",
        "Put related values under one name, and build one.",
        ["structs"],
        [prose("A struct groups several values under one name. You will know the idea "
               "as a struct in C or Go, or as a small class with no inheritance."),
         code("struct User {\n    name: String,\n    age: u32,\n}\n\n"
              "let u = User {\n    name: String::from(\"amy\"),\n    age: 30,\n};",
              "Every field is named and typed."),
         prose("When you build one you must fill in every field. Rust has no "
               "half-built value and no implicit null, so leaving one out is error "
               "`E0063`."),
         prose("You read a field with a dot, the same as in most languages. Writing "
               "to one needs the binding to be `mut`."),
         code("println!(\"{}\", u.name);\n\nlet mut u = u;\nu.age = 31;",
              "Reading is free. Writing needs mut."),
         prose("When most fields come from an existing value, `..base` fills in the "
               "rest. It has to come last, and it consumes `base` unless every field "
               "it copies is a simple value."),
         code("let older = User {\n    age: 40,\n    ..u\n};",
              "age is new, name comes from u.")],
        source=CR("Day 1 Afternoon: User-Defined Types")),

    reuse("structs-and-enums.003", "002",
          goal="Raise the count by one and take every other field from the base order.",
          hints=["The new count is built from the old one.",
                 "One piece of syntax copies all the remaining fields."],
          explanation="`count: base.count + 1` computes the new value, and `..base` "
                      "fills in every field you did not name. The update syntax must "
                      "come last in the literal. Without it you would have to write "
                      "out `id` and `express` by hand, and adding a fourth field later "
                      "would break the code."),

    # CR's instructor note on type aliases: "A newtype is often a better
    # alternative since it creates a distinct type. Prefer
    # struct InventoryCount(usize) to type InventoryCount = usize."
    minimal_edit(
        "003", "One Field, New Type",
        "Wrap a number so the compiler stops treating it as just a number.",
        ["structs"], 2,
        "struct Meters⟦decl⟧\n\n"
        "fn add(a: Meters, b: Meters) -> Meters {\n"
        "    Meters(a.0 + b.0)\n"
        "}\n\n"
        "fn main() {\n"
        "    let total = add(Meters(3), Meters(4));\n"
        "    println!(\"{}\", total.0);\n"
        "}\n",
        [slot("decl", "the body", ["(i32);", "(f64);", " { value: i32 }"],
              original=" { value: i32 }")],
        ["#[test]\nfn adds() {\n"
         "    assert_eq!(add(Meters(3), Meters(4)).0, 7);\n"
         "    assert_eq!(add(Meters(0), Meters(0)).0, 0);\n}"],
        ["The code builds one with `Meters(3)` and reads it with `.0`.",
         "`Meters(3)` hands the field a whole number."],
        "A struct written `struct Meters(i32);` is a tuple struct. Its field has "
        "no name, so you build it like a function call and read it with `.0`. "
        "The named form `{ value: i32 }` has to be built with `Meters { value: 3 }` "
        "instead, so the calls here stop compiling. Choosing `f64` breaks too, "
        "because `Meters(3)` hands it a whole number. This one-field wrapper is "
        "called a newtype. It is how you stop a length being mistaken for a "
        "weight. Both are numbers, but they are no longer the same type.",
        source=CR("Day 1 Afternoon: User-Defined Types (Tuple Structs)")),

    lesson(
        "004", "Methods on Your Type",
        "Behavior goes in an impl block, and the first parameter decides who keeps the value.",
        ["structs"],
        [prose("Behavior goes in an `impl` block next to the type. Inside it, a method "
               "takes `self` as its first parameter, which is how the caller's value "
               "gets in."),
         prose("There are two forms you need now, and the choice is not style. It "
               "decides whether the caller still owns the value afterwards."),
         code("impl User {\n"
              "    fn greet(&self) -> String {\n"
              "        format!(\"hi {}\", self.name)\n"
              "    }\n\n"
              "    fn into_name(self) -> String {\n"
              "        self.name\n"
              "    }\n}",
              "&self borrows. self takes the value away."),
         prose("`&self` borrows the value for the length of the call. The caller keeps "
               "it, so you can call the method as many times as you want."),
         prose("`self` takes the value into the method. After one call the caller no "
               "longer has it, and a second call is error `E0382`. Use this form only "
               "when the method really does consume the value, such as turning it into "
               "something else."),
         prose("When in doubt use `&self`. The ownership decks explain why this rule "
               "exists at all.")],
        source=CR("Day 2 Morning: Methods and Traits")),

    reuse("structs-and-enums.002", "005",
          goal="Give User a typed field, then read it in the method without taking it away.",
          hints=["A field needs a name and a type.",
                 "The method is called on a value the caller still wants afterwards."],
          explanation="A field is written `name: Type`, so `name: String` declares one. "
                      "The method then takes `&self`, which borrows the user for the "
                      "call and leaves the caller holding it. Taking `self` would "
                      "compile here but would consume the user, and the caller could "
                      "never use it again."),

    reuse("structs-and-enums.004", "006",
          goal="cost() is called twice on the same package. Pick the form that survives the first call.",
          hints=["Look at how many times main calls the method.",
                 "One of these forms takes the package away."],
          explanation="`&self` borrows the package for the call, so the second call "
                      "still has something to work with. `self` would consume it on the "
                      "first call and the second is then error `E0382`, use of a moved "
                      "value. This is the most common shape of that error in real code."),
], concepts=[
    concept("structs", "Structs", "Data shapes",
            "A struct groups several named, typed values under one type name.",
            ["A struct groups several values under one name. Each field has a name and "
             "a type, and you must fill in every field when you build one. Rust has no "
             "half-built values, so a missing field is error `E0063`.",
             "Behavior goes in an `impl` block. A method's first parameter is `&self` "
             "when it only needs to read, and the caller keeps the value. It is `self` "
             "when the method consumes the value, and after one call the caller no "
             "longer has it.",
             "When most fields come from an existing value, `..base` fills in the rest. "
             "It must come last in the literal."],
            "struct User {\n    name: String,\n}\n\n"
            "impl User {\n    fn greet(&self) -> String {\n"
            "        format!(\"hi {}\", self.name)\n    }\n}",
            "&self borrows, so the caller keeps the user."),
])
