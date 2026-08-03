//! Step-12 CLI: evaluate one submission against one puzzle, locally.
//!
//!     cargo run -p evaluator --bin evaluate -- <puzzle.json> < submission.json
//!
//! Reads the submission (JSON, `{"puzzle_id", "puzzle_version", "operations"}`)
//! from stdin, prints the `EvalResult` JSON to stdout. Exit 0 even for failed
//! submissions — a compile error is a result; only infrastructure errors exit 1.

use std::io::Read;
use std::process::ExitCode;

use evaluator::{Toolchain, evaluate};
use puzzle_schema::{Puzzle, Submission};

fn main() -> ExitCode {
    let Some(puzzle_path) = std::env::args().nth(1) else {
        eprintln!("usage: evaluate <puzzle.json> < submission.json");
        return ExitCode::from(2);
    };
    let puzzle: Puzzle = match std::fs::read_to_string(&puzzle_path)
        .map_err(|e| e.to_string())
        .and_then(|t| serde_json::from_str(&t).map_err(|e| e.to_string()))
    {
        Ok(p) => p,
        Err(e) => {
            eprintln!("cannot load puzzle {puzzle_path}: {e}");
            return ExitCode::FAILURE;
        }
    };

    let mut input = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut input) {
        eprintln!("cannot read stdin: {e}");
        return ExitCode::FAILURE;
    }
    let submission: Submission = match serde_json::from_str(&input) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("invalid submission JSON: {e}");
            return ExitCode::FAILURE;
        }
    };
    if submission.puzzle_id != puzzle.id || submission.puzzle_version != puzzle.version {
        eprintln!(
            "submission targets {} v{}, puzzle file is {} v{}",
            submission.puzzle_id, submission.puzzle_version, puzzle.id, puzzle.version
        );
        return ExitCode::FAILURE;
    }

    match evaluate(&puzzle, &submission.operations, &Toolchain::default()) {
        Ok(result) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&result).expect("result serializes")
            );
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("evaluation infrastructure error: {e}");
            ExitCode::FAILURE
        }
    }
}
