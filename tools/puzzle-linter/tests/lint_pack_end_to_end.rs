//! Full pack lint against the real toolchain: structure checks, whole-space
//! evaluation, sidecar generation, and CI check mode.

use std::fs;

use evaluator::Toolchain;
use puzzle_linter::{Options, lint_pack, load_concepts};
use puzzle_schema::Outcomes;

const PUZZLE: &str = r##"{
  "schema_version": 1,
  "id": "move-or-borrow.001",
  "version": 1,
  "title": "Use It Twice",
  "track": "move-or-borrow",
  "concepts": ["move", "borrow"],
  "difficulty": 1,
  "goal": "Make both print statements valid.",
  "template": "fn main() {\n    let name = String::from(\"Jazz\");\n    print_name(⟦arg⟧);\n    println!(\"{name}\");\n}\n\nfn print_name(x: ⟦param_ty⟧) {\n    println!(\"{x}\");\n}\n",
  "interaction": {
    "type": "minimal-edit",
    "slots": [
      { "id": "arg", "original": "name",
        "choices": [
          { "id": "c1", "text": "name" },
          { "id": "c2", "text": "&name" },
          { "id": "c3", "text": "name.clone()" } ] },
      { "id": "param_ty", "original": "String",
        "choices": [
          { "id": "t1", "text": "String" },
          { "id": "t2", "text": "&String" },
          { "id": "t3", "text": "&str" } ] }
    ]
  },
  "evaluation": {
    "tests": ["#[test]\nfn runs() { main(); }"],
    "metrics": ["clone_count", "token_edits"]
  },
  "scoring": {
    "primary": "clone_count",
    "secondary": ["token_edits"],
    "fluent": { "clone_count": 0 },
    "optimal": { "clone_count": 0, "token_edits": 2 }
  },
  "hints": [],
  "explanation": "",
  "prerequisites": [],
  "source": { "origin": "original", "license": null, "attribution": null }
}"##;

#[test]
fn lints_a_pack_and_generates_verifiable_outcomes() {
    let dir = tempfile::tempdir().unwrap();
    let pack_dir = dir.path();
    fs::write(
        pack_dir.join("pack.json"),
        r#"{ "schema_version": 1, "id": "move-or-borrow", "title": "Move or Borrow",
             "toolchain": "1.", "order": ["move-or-borrow.001"] }"#,
    )
    .unwrap();
    fs::create_dir(pack_dir.join("puzzles")).unwrap();
    fs::write(pack_dir.join("puzzles/move-or-borrow.001.json"), PUZZLE).unwrap();

    let toolchain = Toolchain::default();

    // Generate.
    let report = lint_pack(pack_dir, &toolchain, &Options::default()).unwrap();
    assert!(report.ok(), "errors: {:?}", report.errors);
    assert_eq!(report.puzzles_checked, 1);
    assert_eq!(report.submissions_evaluated, 9);
    assert_eq!(report.outcomes_written, 1);

    let sidecar: Outcomes = serde_json::from_str(
        &fs::read_to_string(pack_dir.join("outcomes/move-or-borrow.001.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(
        sidecar.outcomes.len(),
        9,
        "one outcome per legal submission"
    );

    // CI check mode passes on fresh outcomes…
    let check = lint_pack(
        pack_dir,
        &toolchain,
        &Options {
            check: true,
            skip_eval: false,
            concept_ids: None,
        },
    )
    .unwrap();
    assert!(check.ok(), "errors: {:?}", check.errors);

    // …and fails once they are tampered with.
    fs::write(pack_dir.join("outcomes/move-or-borrow.001.json"), "{}").unwrap();
    let stale = lint_pack(
        pack_dir,
        &toolchain,
        &Options {
            check: true,
            skip_eval: false,
            concept_ids: None,
        },
    )
    .unwrap();
    assert!(
        stale.errors.iter().any(|e| e.contains("stale")),
        "errors: {:?}",
        stale.errors
    );
}

#[test]
fn structural_failures_are_reported_without_compiling() {
    let dir = tempfile::tempdir().unwrap();
    let pack_dir = dir.path();
    fs::write(
        pack_dir.join("pack.json"),
        r#"{ "schema_version": 1, "id": "move-or-borrow", "title": "t",
             "toolchain": "1.", "order": ["move-or-borrow.001", "move-or-borrow.002"] }"#,
    )
    .unwrap();
    fs::create_dir(pack_dir.join("puzzles")).unwrap();
    // 001 is missing entirely; 002 declares a prerequisite that is not in the pack.
    let broken = PUZZLE
        .replace("move-or-borrow.001", "move-or-borrow.002")
        .replace(
            "\"prerequisites\": []",
            "\"prerequisites\": [\"move-or-borrow.999\"]",
        );
    fs::write(pack_dir.join("puzzles/move-or-borrow.002.json"), broken).unwrap();

    let report = lint_pack(
        pack_dir,
        &Toolchain::default(),
        &Options {
            check: false,
            skip_eval: true,
            concept_ids: None,
        },
    )
    .unwrap();
    assert!(report.errors.iter().any(|e| e.contains("cannot read")));
    assert!(report.errors.iter().any(|e| e.contains("prerequisite")));
    assert_eq!(report.submissions_evaluated, 0);
}

#[test]
fn concept_references_are_enforced_when_a_library_is_given() {
    let dir = tempfile::tempdir().unwrap();
    let pack_dir = dir.path().join("pack");
    fs::create_dir(&pack_dir).unwrap();
    fs::write(
        pack_dir.join("pack.json"),
        r#"{ "schema_version": 1, "id": "move-or-borrow", "title": "t",
             "toolchain": "1.", "order": ["move-or-borrow.001"] }"#,
    )
    .unwrap();
    fs::create_dir(pack_dir.join("puzzles")).unwrap();
    fs::write(pack_dir.join("puzzles/move-or-borrow.001.json"), PUZZLE).unwrap();

    // Library that knows "move" but not "borrow" (the puzzle references both),
    // plus one broken file that must be reported without sinking the rest.
    let lib = dir.path().join("concepts");
    fs::create_dir(&lib).unwrap();
    fs::write(
        lib.join("move.json"),
        r#"{ "schema_version": 1, "id": "move", "title": "Moves",
             "summary": "s", "lecture": ["p"] }"#,
    )
    .unwrap();
    fs::write(lib.join("broken.json"), r#"{ "id": "mismatch" }"#).unwrap();

    let (ids, errors) = load_concepts(&lib).unwrap();
    assert_eq!(ids.len(), 1, "only the valid concept loads");
    assert_eq!(errors.len(), 1, "the broken file is reported");

    let report = lint_pack(
        &pack_dir,
        &Toolchain::default(),
        &Options {
            check: false,
            skip_eval: true,
            concept_ids: Some(ids),
        },
    )
    .unwrap();
    assert!(
        report
            .errors
            .iter()
            .any(|e| e.contains("unknown concept \"borrow\"")),
        "errors: {:?}",
        report.errors
    );
}
