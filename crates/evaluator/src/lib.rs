//! # evaluator
//!
//! The evaluation engine: reconstructed source → rustc → tests → clippy →
//! metrics → rank. One implementation serves the puzzle linter (precomputing
//! outcomes sidecars), the future local CLI (build-order step 12), and the
//! compiler workers behind the API.
//!
//! Infrastructure failures (rustc missing, io) are `Err(EvalError)`; everything
//! about the *submission* — including illegal operations — is an `Ok(EvalResult)`.

pub mod metrics;
pub mod rustc_json;

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::Command;

use puzzle_schema::{
    Diagnostic, EvalResult, EvalStatus, Metric, Operation, Puzzle, Rank, Scoring,
    reconstruct_with_spans,
};
use thiserror::Error;

#[derive(Debug, Clone)]
pub struct Toolchain {
    pub rustc: PathBuf,
    pub clippy_driver: PathBuf,
    pub edition: String,
    /// Explicit linker for direct rustc invocations. Cargo's config does not
    /// apply here, so PATH shadowing of `cc` (see ~/.cargo/config.toml on dev
    /// machines) would otherwise break linking. Populated from `$CC` when set.
    pub linker: Option<PathBuf>,
}

impl Default for Toolchain {
    fn default() -> Self {
        Toolchain {
            rustc: "rustc".into(),
            clippy_driver: "clippy-driver".into(),
            edition: "2024".into(),
            linker: std::env::var_os("CC").map(PathBuf::from),
        }
    }
}

impl Toolchain {
    /// `rustc --version` output, e.g. "rustc 1.97.1 (…)".
    pub fn rustc_version(&self) -> Result<String, EvalError> {
        let out = Command::new(&self.rustc).arg("--version").output()?;
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }
}

#[derive(Debug, Error)]
pub enum EvalError {
    #[error("io/spawn failure: {0}")]
    Io(#[from] std::io::Error),
    #[error("clippy-driver not runnable ({0}) — install with: rustup component add clippy")]
    ClippyMissing(String),
    #[error("lesson puzzles are not evaluatable")]
    NotEvaluatable,
}

/// Evaluate one submission end to end. Deterministic for a given
/// (puzzle, operations, toolchain) — that determinism is what makes the
/// precomputed outcomes sidecar equivalent to live evaluation.
pub fn evaluate(
    puzzle: &Puzzle,
    operations: &[Operation],
    toolchain: &Toolchain,
) -> Result<EvalResult, EvalError> {
    let (Some(evaluation), Some(scoring)) = (&puzzle.evaluation, &puzzle.scoring) else {
        return Err(EvalError::NotEvaluatable);
    };
    let reconstruction = match reconstruct_with_spans(puzzle, operations) {
        Ok(r) => r,
        Err(e) => {
            return Ok(EvalResult {
                status: EvalStatus::Invalid,
                rank: None,
                metrics: BTreeMap::new(),
                diagnostics: vec![Diagnostic {
                    category: "invalid_operations".into(),
                    message: e.to_string(),
                    slot_ids: vec![],
                    rust_code: None,
                }],
            });
        }
    };

    let full_source = with_tests(&reconstruction.source, &evaluation.tests);
    let dir = tempfile::tempdir()?;
    let src_path = dir.path().join("main.rs");
    let bin_path = dir.path().join("submission");
    std::fs::write(&src_path, &full_source)?;

    let has_tests = !evaluation.tests.is_empty();
    let has_main = reconstruction.source.contains("fn main");

    // Compile. Tests need the harness; a main-less, test-less fragment is
    // typechecked as a library (Solved = it compiles).
    let mut cmd = Command::new(&toolchain.rustc);
    cmd.arg("--edition")
        .arg(&toolchain.edition)
        .arg("--error-format=json")
        .current_dir(dir.path());
    if let Some(linker) = &toolchain.linker {
        cmd.arg("-C").arg(format!("linker={}", linker.display()));
    }
    if has_tests {
        cmd.arg("--test").arg("-o").arg(&bin_path);
    } else if has_main {
        cmd.arg("-o").arg(&bin_path);
    } else {
        cmd.arg("--crate-type=lib").arg("--emit=metadata");
    }
    cmd.arg(&src_path);
    let compile = cmd.output()?;

    if !compile.status.success() {
        let diags = rustc_json::parse_stderr(&String::from_utf8_lossy(&compile.stderr));
        return Ok(EvalResult {
            status: EvalStatus::CompileError,
            rank: None,
            metrics: BTreeMap::new(),
            diagnostics: rustc_json::to_puzzle_diagnostics(&diags, &reconstruction),
        });
    }

    if has_tests {
        let run = Command::new(&bin_path).current_dir(dir.path()).output()?;
        if !run.status.success() {
            let stdout = String::from_utf8_lossy(&run.stdout);
            let summary = stdout
                .lines()
                .find(|l| l.starts_with("test result:"))
                .unwrap_or("tests failed")
                .to_string();
            return Ok(EvalResult {
                status: EvalStatus::TestFailure,
                rank: None,
                metrics: BTreeMap::new(),
                diagnostics: vec![Diagnostic {
                    category: "test_failure".into(),
                    message: summary,
                    slot_ids: vec![],
                    rust_code: None,
                }],
            });
        }
    }

    let wanted = &evaluation.metrics;
    let mut metric_values = metrics::compute(puzzle, operations, &reconstruction, wanted);
    if wanted.contains(&Metric::ClippyWarningCount) {
        let count =
            clippy_warning_count(&evaluation.clippy.deny, &src_path, has_main, toolchain)?;
        metric_values.insert(Metric::ClippyWarningCount, count);
    }

    let rank = rank_for(scoring, &metric_values);
    Ok(EvalResult {
        status: EvalStatus::Solved,
        rank: Some(rank),
        metrics: metric_values,
        diagnostics: vec![],
    })
}

/// Append the puzzle's tests as a `#[cfg(test)]` module.
fn with_tests(source: &str, tests: &[String]) -> String {
    if tests.is_empty() {
        return source.to_string();
    }
    let mut out = String::from(source);
    out.push_str(
        "\n#[cfg(test)]\nmod rustchap_tests {\n    #[allow(unused_imports)]\n    use super::*;\n",
    );
    for test in tests {
        for line in test.lines() {
            out.push_str("    ");
            out.push_str(line);
            out.push('\n');
        }
    }
    out.push_str("}\n");
    out
}

/// Warnings emitted by clippy that match the puzzle's `clippy.deny` list
/// (or any `clippy::*` warning when the list is empty).
fn clippy_warning_count(
    deny: &[String],
    src_path: &std::path::Path,
    has_main: bool,
    toolchain: &Toolchain,
) -> Result<u32, EvalError> {
    let mut cmd = Command::new(&toolchain.clippy_driver);
    cmd.arg("--edition")
        .arg(&toolchain.edition)
        .arg("--error-format=json")
        .arg("--emit=metadata")
        // Without this, --emit=metadata drops libmain.rmeta into the caller's cwd.
        .current_dir(src_path.parent().expect("src lives in the scratch dir"));
    if !has_main {
        cmd.arg("--crate-type=lib");
    }
    for lint in deny {
        cmd.arg("-W").arg(lint);
    }
    cmd.arg(src_path);
    let out = cmd
        .output()
        .map_err(|e| EvalError::ClippyMissing(e.to_string()))?;
    let diags = rustc_json::parse_stderr(&String::from_utf8_lossy(&out.stderr));
    let count = diags
        .iter()
        .filter(|d| d.level == "warning")
        .filter_map(|d| d.code.as_ref())
        .filter(|c| {
            if deny.is_empty() {
                c.code.starts_with("clippy::")
            } else {
                deny.contains(&c.code)
            }
        })
        .count();
    Ok(count as u32)
}

/// Mechanical rank: `Optimal` when every optimal threshold holds
/// (`metric <= value`), else `Fluent` when every fluent threshold holds, else
/// `Solved`. A metric missing from the computed set fails its threshold.
pub fn rank_for(scoring: &Scoring, metrics: &BTreeMap<Metric, u32>) -> Rank {
    let meets = |thresholds: &BTreeMap<Metric, u32>| {
        thresholds
            .iter()
            .all(|(m, max)| metrics.get(m).is_some_and(|v| v <= max))
    };
    if !scoring.optimal.is_empty() && meets(&scoring.optimal) {
        Rank::Optimal
    } else if !scoring.fluent.is_empty() && meets(&scoring.fluent) {
        Rank::Fluent
    } else {
        Rank::Solved
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rank_thresholds_are_all_or_nothing() {
        let scoring = Scoring {
            primary: Metric::CloneCount,
            secondary: vec![],
            fluent: BTreeMap::from([(Metric::CloneCount, 0)]),
            optimal: BTreeMap::from([(Metric::CloneCount, 0), (Metric::TokenEdits, 2)]),
        };
        let solved = BTreeMap::from([(Metric::CloneCount, 1), (Metric::TokenEdits, 1)]);
        let fluent = BTreeMap::from([(Metric::CloneCount, 0), (Metric::TokenEdits, 3)]);
        let optimal = BTreeMap::from([(Metric::CloneCount, 0), (Metric::TokenEdits, 2)]);
        assert_eq!(rank_for(&scoring, &solved), Rank::Solved);
        assert_eq!(rank_for(&scoring, &fluent), Rank::Fluent);
        assert_eq!(rank_for(&scoring, &optimal), Rank::Optimal);
    }

    #[test]
    fn empty_thresholds_never_award_the_rank() {
        let scoring = Scoring {
            primary: Metric::CloneCount,
            secondary: vec![],
            fluent: BTreeMap::new(),
            optimal: BTreeMap::new(),
        };
        assert_eq!(
            rank_for(&scoring, &BTreeMap::from([(Metric::CloneCount, 0)])),
            Rank::Solved
        );
    }
}
