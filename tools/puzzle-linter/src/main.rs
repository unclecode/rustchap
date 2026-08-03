//! CLI: `cargo run -p puzzle-linter -- [--check] [--skip-eval] <pack-dir>...`

use std::path::PathBuf;
use std::process::ExitCode;

use evaluator::Toolchain;
use puzzle_linter::{Options, lint_pack};

fn main() -> ExitCode {
    let mut opts = Options::default();
    let mut dirs: Vec<PathBuf> = Vec::new();
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--check" => opts.check = true,
            "--skip-eval" => opts.skip_eval = true,
            other if other.starts_with('-') => {
                eprintln!("unknown flag {other}");
                eprintln!("usage: puzzle-linter [--check] [--skip-eval] <pack-dir>...");
                return ExitCode::from(2);
            }
            path => dirs.push(PathBuf::from(path)),
        }
    }
    if dirs.is_empty() {
        eprintln!("usage: puzzle-linter [--check] [--skip-eval] <pack-dir>...");
        return ExitCode::from(2);
    }

    let toolchain = Toolchain::default();
    let mut failed = false;
    for dir in &dirs {
        match lint_pack(dir, &toolchain, &opts) {
            Ok(report) => {
                println!(
                    "pack {}: {} puzzles, {} submissions evaluated, {} outcomes written",
                    report.pack_id,
                    report.puzzles_checked,
                    report.submissions_evaluated,
                    report.outcomes_written
                );
                for warning in &report.warnings {
                    println!("  warn: {warning}");
                }
                for error in &report.errors {
                    println!("  ERROR: {error}");
                }
                if !report.ok() {
                    failed = true;
                }
            }
            Err(e) => {
                eprintln!("{}: {e:#}", dir.display());
                failed = true;
            }
        }
    }
    if failed {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
