//! End-to-end contract test: a realistic puzzle JSON round-trips through
//! parsing, validation, enumeration, reconstruction, and scoring helpers.

use puzzle_schema::*;

const EXAMPLE: &str = r##"{
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
      {
        "id": "arg",
        "original": "name",
        "label": "argument",
        "choices": [
          { "id": "c1", "text": "name" },
          { "id": "c2", "text": "&name" },
          { "id": "c3", "text": "name.clone()" }
        ]
      },
      {
        "id": "param_ty",
        "original": "String",
        "choices": [
          { "id": "t1", "text": "String" },
          { "id": "t2", "text": "&String" },
          { "id": "t3", "text": "&str" }
        ]
      }
    ]
  },
  "evaluation": {
    "tests": ["#[test]\nfn compiles_and_runs() { main(); }"],
    "clippy": { "deny": ["clippy::redundant_clone"] },
    "metrics": ["clone_count", "token_edits"]
  },
  "scoring": {
    "primary": "clone_count",
    "secondary": ["token_edits"],
    "fluent": { "clone_count": 0 },
    "optimal": { "clone_count": 0, "token_edits": 2 }
  },
  "hints": ["Does print_name need to own the name?"],
  "explanation": "Borrowing lets the caller keep ownership; &str accepts both.",
  "prerequisites": [],
  "source": { "origin": "original", "license": null, "attribution": null }
}"##;

fn example() -> Puzzle {
    serde_json::from_str(EXAMPLE).expect("example puzzle parses")
}

fn select(slot: &str, choice: &str) -> Operation {
    Operation::Select {
        slot_id: slot.to_string(),
        choice_id: choice.to_string(),
    }
}

#[test]
fn example_is_valid() {
    validate_puzzle(&example()).expect("example passes validation");
}

#[test]
fn serde_round_trip_preserves_structure() {
    let puzzle = example();
    let json = serde_json::to_string(&puzzle).unwrap();
    let back: Puzzle = serde_json::from_str(&json).unwrap();
    assert_eq!(back.id, puzzle.id);
    assert_eq!(
        serde_json::to_value(&back).unwrap(),
        serde_json::to_value(&puzzle).unwrap()
    );
}

#[test]
fn reconstructs_the_borrowing_answer() {
    let source = reconstruct(&example(), &[select("arg", "c2"), select("param_ty", "t3")]).unwrap();
    assert!(source.contains("print_name(&name);"));
    assert!(source.contains("fn print_name(x: &str)"));
    assert!(!source.contains('⟦'));
}

#[test]
fn rejects_incomplete_and_unknown_operations() {
    let puzzle = example();
    assert!(matches!(
        reconstruct(&puzzle, &[select("arg", "c2")]),
        Err(template::ReconstructError::UnassignedSlot(_))
    ));
    assert!(matches!(
        reconstruct(&puzzle, &[select("arg", "nope"), select("param_ty", "t3")]),
        Err(template::ReconstructError::UnknownChoice { .. })
    ));
}

#[test]
fn token_edits_counts_departures_from_original() {
    let puzzle = example();
    // Keep both originals: zero edits.
    assert_eq!(
        token_edits(&puzzle, &[select("arg", "c1"), select("param_ty", "t1")]),
        Some(0)
    );
    // The optimal answer changes both tokens.
    assert_eq!(
        token_edits(&puzzle, &[select("arg", "c2"), select("param_ty", "t3")]),
        Some(2)
    );
}

#[test]
fn enumeration_covers_the_whole_space_with_unique_hashes() {
    let puzzle = example();
    let all = enumerate_submissions(&puzzle);
    assert_eq!(all.len() as u128, submission_space(&puzzle)); // 3 * 3 = 9
    assert_eq!(all.len(), 9);

    let hashes: std::collections::BTreeSet<String> = all.iter().map(|ops| ops_hash(ops)).collect();
    assert_eq!(hashes.len(), 9, "every submission hashes uniquely");

    for ops in &all {
        reconstruct(&puzzle, ops).expect("every enumerated submission reconstructs");
    }
}

#[test]
fn validation_catches_broken_puzzles() {
    // Marker without a slot definition.
    let mut broken = example();
    broken.template = Some("fn f() { ⟦ghost⟧ }".to_string());
    let errors = validate_puzzle(&broken).unwrap_err();
    assert!(
        errors
            .iter()
            .any(|e| matches!(e, validate::ValidationError::MarkerWithoutSlot(_)))
    );
    assert!(
        errors
            .iter()
            .any(|e| matches!(e, validate::ValidationError::SlotWithoutMarker(_)))
    );

    // Minimal-edit slot whose original is not offered as a choice.
    let mut broken = example();
    if let Interaction::MinimalEdit { slots } = &mut broken.interaction {
        slots[0].original = Some("something_else".to_string());
    }
    let errors = validate_puzzle(&broken).unwrap_err();
    assert!(
        errors
            .iter()
            .any(|e| matches!(e, validate::ValidationError::OriginalNotInChoices(_)))
    );

    // Scoring references a metric the evaluation does not compute.
    let mut broken = example();
    broken.evaluation.metrics = vec![Metric::TokenEdits];
    let errors = validate_puzzle(&broken).unwrap_err();
    assert!(
        errors
            .iter()
            .any(|e| matches!(e, validate::ValidationError::UnlistedMetric(_)))
    );

    // Imported puzzle without a licence.
    let mut broken = example();
    broken.source.origin = "rustlings".to_string();
    let errors = validate_puzzle(&broken).unwrap_err();
    assert!(
        errors
            .iter()
            .any(|e| matches!(e, validate::ValidationError::MissingLicense))
    );
}

#[test]
fn arrangement_and_best_solution_reconstruct() {
    let arrangement = serde_json::json!({
        "type": "block-arrangement",
        "fixed_prefix": "let evens: Vec<i32> = values",
        "blocks": [
            { "id": "iter",    "text": ".iter()" },
            { "id": "filter",  "text": ".filter(|x| *x % 2 == 0)" },
            { "id": "copied",  "text": ".copied()" },
            { "id": "collect", "text": ".collect()" }
        ],
        "fixed_suffix": ";"
    });
    let mut puzzle = example();
    puzzle.template = None;
    puzzle.interaction = serde_json::from_value(arrangement).unwrap();
    puzzle.scoring.secondary.clear(); // token_edits no longer applies
    puzzle.scoring.optimal.remove(&Metric::TokenEdits);
    puzzle.evaluation.metrics = vec![Metric::CloneCount];

    validate_puzzle(&puzzle).expect("arrangement puzzle is valid");
    assert_eq!(submission_space(&puzzle), 24); // 4!

    let order: Vec<String> = ["iter", "filter", "copied", "collect"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let source = reconstruct(&puzzle, &[Operation::Arrange { order }]).unwrap();
    assert_eq!(
        source,
        "let evens: Vec<i32> = values.iter().filter(|x| *x % 2 == 0).copied().collect();"
    );

    let best = serde_json::json!({
        "type": "best-solution",
        "candidates": [
            { "id": "alloc",    "code": "fn first(s: &str) -> String { s.split(' ').next().unwrap().to_string() }" },
            { "id": "borrowed", "code": "fn first(s: &str) -> &str { s.split(' ').next().unwrap() }" }
        ]
    });
    puzzle.interaction = serde_json::from_value(best).unwrap();
    validate_puzzle(&puzzle).expect("best-solution puzzle is valid");
    let source = reconstruct(
        &puzzle,
        &[Operation::Pick {
            candidate_id: "borrowed".to_string(),
        }],
    )
    .unwrap();
    assert!(source.contains("-> &str"));
}
