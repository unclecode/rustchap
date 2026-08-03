//! End-to-end evaluation against the real installed rustc: the "Use It Twice"
//! puzzle from the schema tests, run through compile/test/metrics/rank.

use std::collections::BTreeMap;

use evaluator::{Toolchain, evaluate};
use puzzle_schema::*;

fn puzzle() -> Puzzle {
    Puzzle {
        schema_version: 1,
        id: "move-or-borrow.001".into(),
        version: 1,
        title: "Use It Twice".into(),
        track: "move-or-borrow".into(),
        concepts: vec!["move".into(), "borrow".into()],
        difficulty: 1,
        goal: "Make both print statements valid.".into(),
        template: Some(
            "fn main() {\n    let name = String::from(\"Jazz\");\n    print_name(⟦arg⟧);\n    println!(\"{name}\");\n}\n\nfn print_name(x: ⟦param_ty⟧) {\n    println!(\"{x}\");\n}\n"
                .into(),
        ),
        interaction: Interaction::MinimalEdit {
            slots: vec![
                Slot {
                    id: "arg".into(),
                    original: Some("name".into()),
                    label: Some("argument".into()),
                    choices: vec![
                        Choice { id: "c1".into(), text: "name".into() },
                        Choice { id: "c2".into(), text: "&name".into() },
                        Choice { id: "c3".into(), text: "name.clone()".into() },
                    ],
                },
                Slot {
                    id: "param_ty".into(),
                    original: Some("String".into()),
                    label: None,
                    choices: vec![
                        Choice { id: "t1".into(), text: "String".into() },
                        Choice { id: "t2".into(), text: "&String".into() },
                        Choice { id: "t3".into(), text: "&str".into() },
                    ],
                },
            ],
        },
        evaluation: Evaluation {
            tests: vec!["#[test]\nfn runs() { main(); }".into()],
            clippy: Clippy::default(),
            metrics: vec![Metric::CloneCount, Metric::TokenEdits],
        },
        scoring: Scoring {
            primary: Metric::CloneCount,
            secondary: vec![Metric::TokenEdits],
            fluent: BTreeMap::from([(Metric::CloneCount, 0)]),
            optimal: BTreeMap::from([(Metric::CloneCount, 0), (Metric::TokenEdits, 2)]),
        },
        hints: vec![],
        explanation: String::new(),
        prerequisites: vec![],
        source: SourceInfo { origin: "original".into(), license: None, attribution: None },
    }
}

fn select(slot: &str, choice: &str) -> Operation {
    Operation::Select {
        slot_id: slot.into(),
        choice_id: choice.into(),
    }
}

#[test]
fn optimal_answer_solves_with_rank_optimal() {
    let result = evaluate(
        &puzzle(),
        &[select("arg", "c2"), select("param_ty", "t3")],
        &Toolchain::default(),
    )
    .unwrap();
    assert_eq!(
        result.status,
        EvalStatus::Solved,
        "diags: {:?}",
        result.diagnostics
    );
    assert_eq!(result.rank, Some(Rank::Optimal));
    assert_eq!(result.metrics[&Metric::CloneCount], 0);
    assert_eq!(result.metrics[&Metric::TokenEdits], 2);
}

#[test]
fn clone_answer_solves_but_stays_rank_solved() {
    let result = evaluate(
        &puzzle(),
        &[select("arg", "c3"), select("param_ty", "t1")],
        &Toolchain::default(),
    )
    .unwrap();
    assert_eq!(
        result.status,
        EvalStatus::Solved,
        "diags: {:?}",
        result.diagnostics
    );
    assert_eq!(result.rank, Some(Rank::Solved));
    assert_eq!(result.metrics[&Metric::CloneCount], 1);
}

#[test]
fn move_error_is_categorized_and_mapped_to_slots() {
    let result = evaluate(
        &puzzle(),
        &[select("arg", "c1"), select("param_ty", "t1")],
        &Toolchain::default(),
    )
    .unwrap();
    assert_eq!(result.status, EvalStatus::CompileError);
    assert_eq!(result.rank, None);
    let diag = result
        .diagnostics
        .iter()
        .find(|d| d.category == "move_error")
        .expect("expected a move_error diagnostic");
    assert_eq!(diag.rust_code.as_deref(), Some("E0382"));
}

#[test]
fn invalid_operations_are_a_result_not_an_error() {
    let result = evaluate(&puzzle(), &[select("arg", "bogus")], &Toolchain::default()).unwrap();
    assert_eq!(result.status, EvalStatus::Invalid);
    assert_eq!(result.diagnostics[0].category, "invalid_operations");
}
