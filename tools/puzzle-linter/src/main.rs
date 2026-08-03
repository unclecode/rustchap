//! CLI: `cargo run -p puzzle-linter -- [--check] [--skip-eval] [--concepts <dir>] <pack-dir>...`

use std::path::PathBuf;
use std::process::ExitCode;

use evaluator::Toolchain;
use puzzle_linter::{Options, lint_pack, load_concepts};

const USAGE: &str = "usage: puzzle-linter [--check] [--skip-eval] [--concepts <dir>] <pack-dir>...";

fn main() -> ExitCode {
    let mut opts = Options::default();
    let mut concepts_dir: Option<PathBuf> = None;
    let mut dirs: Vec<PathBuf> = Vec::new();

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--check" => opts.check = true,
            "--skip-eval" => opts.skip_eval = true,
            "--concepts" => {
                let Some(dir) = args.next() else {
                    eprintln!("--concepts needs a directory\n{USAGE}");
                    return ExitCode::from(2);
                };
                concepts_dir = Some(PathBuf::from(dir));
            }
            other if other.starts_with('-') => {
                eprintln!("unknown flag {other}\n{USAGE}");
                return ExitCode::from(2);
            }
            path => dirs.push(PathBuf::from(path)),
        }
    }
    if dirs.is_empty() {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    }

    let mut failed = false;
    if let Some(dir) = &concepts_dir {
        match load_concepts(dir) {
            Ok((ids, errors)) => {
                println!("concept library: {} concepts", ids.len());
                for error in &errors {
                    println!("  ERROR: {error}");
                }
                failed |= !errors.is_empty();
                opts.concept_ids = Some(ids);
            }
            Err(e) => {
                eprintln!("{}: {e:#}", dir.display());
                return ExitCode::FAILURE;
            }
        }
    }

    let toolchain = Toolchain::default();
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
