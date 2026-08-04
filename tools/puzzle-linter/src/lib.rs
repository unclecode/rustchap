//! # puzzle-linter
//!
//! What makes the content bank trustworthy (build-order step 6). For a pack it
//! verifies structure (schema, ids, prerequisites, licences via
//! `validate_puzzle`), then evaluates **every** enumerated submission against
//! the real toolchain and writes the outcomes sidecar
//! (`outcomes/<puzzle_id>.json`) that the app bundles for exact offline
//! evaluation. A puzzle only passes if at least one submission solves and at
//! least one reproduces the declared optimal rank.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use evaluator::{Toolchain, evaluate};
use puzzle_schema::{
    Concept, EvalStatus, Interaction, Outcomes, Pack, Puzzle, Rank, enumerate_submissions,
    ops_hash, validate_puzzle,
};

#[derive(Debug, Default)]
pub struct Options {
    /// Verify stored outcomes instead of writing them (CI mode). Evaluation
    /// still runs in full — that is the verification.
    pub check: bool,
    /// Structural checks only; skip compilation entirely.
    pub skip_eval: bool,
    /// Concept library ids (from [`load_concepts`]). When present, every
    /// puzzle `concepts` entry must resolve to one; when absent, the check
    /// is skipped.
    pub concept_ids: Option<BTreeSet<String>>,
}

/// Load and validate the concept library (content/concepts). Returns the valid
/// ids plus any per-file errors — callers report the errors and still get the
/// usable subset.
pub fn load_concepts(dir: &Path) -> Result<(BTreeSet<String>, Vec<String>)> {
    let mut ids = BTreeSet::new();
    let mut errors = Vec::new();
    for entry in fs::read_dir(dir).with_context(|| format!("reading {}", dir.display()))? {
        let path = entry?.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let name = path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        let concept: Concept = match fs::read_to_string(&path)
            .map_err(anyhow::Error::from)
            .and_then(|text| serde_json::from_str(&text).map_err(anyhow::Error::from))
        {
            Ok(c) => c,
            Err(e) => {
                errors.push(format!("concept {name}: {e}"));
                continue;
            }
        };
        if concept.id != name {
            errors.push(format!("concept {name}: file declares id {:?}", concept.id));
            continue;
        }
        if concept.schema_version != 1 {
            errors.push(format!("concept {name}: schema_version must be 1"));
            continue;
        }
        if concept.lecture.is_empty() {
            errors.push(format!("concept {name}: empty lecture"));
            continue;
        }
        ids.insert(concept.id);
    }
    Ok((ids, errors))
}

#[derive(Debug, Default)]
pub struct LintReport {
    pub pack_id: String,
    pub puzzles_checked: usize,
    pub submissions_evaluated: usize,
    pub outcomes_written: usize,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    /// Per-puzzle outcome distribution (for `--summary` content review).
    pub summaries: Vec<String>,
}

impl LintReport {
    pub fn ok(&self) -> bool {
        self.errors.is_empty()
    }
}

pub fn lint_pack(pack_dir: &Path, toolchain: &Toolchain, opts: &Options) -> Result<LintReport> {
    let mut report = LintReport::default();

    let pack_path = pack_dir.join("pack.json");
    let pack: Pack = serde_json::from_str(
        &fs::read_to_string(&pack_path)
            .with_context(|| format!("reading {}", pack_path.display()))?,
    )
    .with_context(|| format!("parsing {}", pack_path.display()))?;
    report.pack_id = pack.id.clone();

    if pack.schema_version != 1 {
        report.errors.push(format!(
            "pack schema_version must be 1, got {}",
            pack.schema_version
        ));
    }
    if pack.order.is_empty() {
        report
            .warnings
            .push("pack has no puzzles — shown locked in the app".to_string());
    }

    if !opts.skip_eval {
        let version = toolchain.rustc_version()?;
        if !version.contains(&pack.toolchain) {
            report.warnings.push(format!(
                "pack pins toolchain {:?} but the linter is running {:?}",
                pack.toolchain, version
            ));
        }
    }

    // Files present but not in the pack order.
    let puzzles_dir = pack_dir.join("puzzles");
    if let Ok(entries) = fs::read_dir(&puzzles_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if let Some(stem) = name.strip_suffix(".json")
                && !pack.order.iter().any(|id| id == stem)
            {
                report
                    .warnings
                    .push(format!("puzzles/{name} exists but is not in pack order"));
            }
        }
    }

    for (index, puzzle_id) in pack.order.iter().enumerate() {
        report.puzzles_checked += 1;
        let path = puzzles_dir.join(format!("{puzzle_id}.json"));
        let text = match fs::read_to_string(&path) {
            Ok(t) => t,
            Err(e) => {
                report
                    .errors
                    .push(format!("{puzzle_id}: cannot read {}: {e}", path.display()));
                continue;
            }
        };
        let puzzle: Puzzle = match serde_json::from_str(&text) {
            Ok(p) => p,
            Err(e) => {
                report
                    .errors
                    .push(format!("{puzzle_id}: invalid JSON: {e}"));
                continue;
            }
        };

        let mut structural_ok = true;
        if puzzle.id != *puzzle_id {
            report
                .errors
                .push(format!("{puzzle_id}: file declares id {:?}", puzzle.id));
            structural_ok = false;
        }
        if puzzle.track != pack.id {
            report.errors.push(format!(
                "{puzzle_id}: track {:?} != pack id {:?}",
                puzzle.track, pack.id
            ));
            structural_ok = false;
        }
        for prereq in &puzzle.prerequisites {
            if !pack.order[..index].contains(prereq) {
                report.errors.push(format!(
                    "{puzzle_id}: prerequisite {prereq:?} does not precede it in pack order"
                ));
                structural_ok = false;
            }
        }
        if let Err(violations) = validate_puzzle(&puzzle) {
            for v in violations {
                report.errors.push(format!("{puzzle_id}: {v}"));
            }
            structural_ok = false;
        }
        if let Some(known) = &opts.concept_ids {
            for concept in &puzzle.concepts {
                if !known.contains(concept) {
                    report.errors.push(format!(
                        "{puzzle_id}: references unknown concept {concept:?} (not in the concept library)"
                    ));
                    structural_ok = false;
                }
            }
        }
        if puzzle.scoring.as_ref().is_some_and(|s| s.optimal.is_empty()) {
            report.warnings.push(format!(
                "{puzzle_id}: scoring.optimal is empty — no submission can rank Optimal"
            ));
        }

        // Lessons are reading nodes: structural checks only, no submissions,
        // no outcomes sidecar (a leftover one would shadow nothing but is cruft).
        if matches!(puzzle.interaction, Interaction::Lesson { .. }) {
            if structural_ok {
                report
                    .summaries
                    .push(format!("{puzzle_id}: lesson (reading node) — no outcomes"));
                let stale = pack_dir.join("outcomes").join(format!("{puzzle_id}.json"));
                if stale.exists() {
                    report.warnings.push(format!(
                        "{puzzle_id}: lesson has a leftover outcomes file — delete outcomes/{puzzle_id}.json"
                    ));
                }
            }
            continue;
        }

        if !structural_ok || opts.skip_eval {
            continue;
        }
        evaluate_puzzle(&puzzle, pack_dir, &pack, toolchain, opts, &mut report)?;
    }

    Ok(report)
}

fn evaluate_puzzle(
    puzzle: &Puzzle,
    pack_dir: &Path,
    pack: &Pack,
    toolchain: &Toolchain,
    opts: &Options,
    report: &mut LintReport,
) -> Result<()> {
    let id = &puzzle.id;
    let mut outcomes = BTreeMap::new();
    let (mut solved, mut optimal, mut fluent, mut failed, mut test_failed) =
        (0u32, 0u32, 0u32, 0u32, 0u32);

    for ops in enumerate_submissions(puzzle) {
        let result = evaluate(puzzle, &ops, toolchain)?;
        report.submissions_evaluated += 1;
        match result.status {
            EvalStatus::Solved => {
                solved += 1;
                match result.rank {
                    Some(Rank::Optimal) => optimal += 1,
                    Some(Rank::Fluent) => fluent += 1,
                    _ => {}
                }
            }
            EvalStatus::TestFailure => {
                test_failed += 1;
                failed += 1;
            }
            _ => failed += 1,
        }
        outcomes.insert(ops_hash(&ops), result);
    }
    report.summaries.push(format!(
        "{id}: {total} submissions — {solved} solved ({optimal} optimal, {fluent} fluent), {failed} failing ({test_failed} test failures)",
        total = outcomes.len(),
    ));

    if solved == 0 {
        report
            .errors
            .push(format!("{id}: no submission solves the puzzle"));
    }
    if optimal == 0 && puzzle.scoring.as_ref().is_some_and(|s| !s.optimal.is_empty()) {
        report.errors.push(format!(
            "{id}: declared optimal thresholds are not reproducible by any submission"
        ));
    }
    let is_best_solution = matches!(puzzle.interaction, Interaction::BestSolution { .. });
    if failed == 0 && !is_best_solution {
        report.warnings.push(format!(
            "{id}: every submission compiles and passes — the puzzle cannot be failed"
        ));
    }

    let sidecar = Outcomes {
        schema_version: 1,
        puzzle_id: puzzle.id.clone(),
        puzzle_version: puzzle.version,
        toolchain: pack.toolchain.clone(),
        outcomes,
    };
    let mut rendered = serde_json::to_string_pretty(&sidecar)?;
    rendered.push('\n');

    let out_dir = pack_dir.join("outcomes");
    let out_path = out_dir.join(format!("{id}.json"));
    if opts.check {
        match fs::read_to_string(&out_path) {
            Ok(existing) if existing == rendered => {}
            Ok(_) => report.errors.push(format!(
                "{id}: outcomes/{id}.json is stale — regenerate with the linter"
            )),
            Err(_) => report
                .errors
                .push(format!("{id}: outcomes/{id}.json is missing")),
        }
    } else {
        fs::create_dir_all(&out_dir)?;
        fs::write(&out_path, rendered)?;
        report.outcomes_written += 1;
    }
    Ok(())
}
