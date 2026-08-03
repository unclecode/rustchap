//! Serde models mirroring `schemas/*.schema.json`. The JSON Schemas are the
//! documented contract; these types plus [`crate::validate`] are the enforced one.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Puzzle {
    pub schema_version: u32,
    pub id: String,
    pub version: u32,
    pub title: String,
    pub track: String,
    pub concepts: Vec<String>,
    pub difficulty: u8,
    pub goal: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
    pub interaction: Interaction,
    pub evaluation: Evaluation,
    pub scoring: Scoring,
    pub hints: Vec<String>,
    pub explanation: String,
    pub prerequisites: Vec<String>,
    pub source: SourceInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Interaction {
    /// Blank or pre-filled slots, pick from a tray. `original` may be null.
    SlotSelection { slots: Vec<Slot> },
    /// Same engine path as slot-selection, but every slot starts at `original`
    /// (which must be one of its choices) and `token_edits` is the score.
    MinimalEdit { slots: Vec<Slot> },
    /// Order all blocks; source = prefix + blocks in order + suffix.
    BlockArrangement {
        fixed_prefix: String,
        blocks: Vec<Block>,
        fixed_suffix: String,
    },
    /// Pick the preferable complete implementation under the stated goal.
    BestSolution { candidates: Vec<Candidate> },
}

impl Interaction {
    /// Slots for the two slot-based interactions, `None` otherwise.
    pub fn slots(&self) -> Option<&[Slot]> {
        match self {
            Interaction::SlotSelection { slots } | Interaction::MinimalEdit { slots } => {
                Some(slots)
            }
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Slot {
    pub id: String,
    /// The token as originally written, or `None` for a blank slot.
    pub original: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    pub choices: Vec<Choice>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Choice {
    pub id: String,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Block {
    pub id: String,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Candidate {
    pub id: String,
    pub code: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Evaluation {
    /// `#[test]` functions appended in a test module to the reconstructed source.
    pub tests: Vec<String>,
    #[serde(default)]
    pub clippy: Clippy,
    pub metrics: Vec<Metric>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Clippy {
    #[serde(default)]
    pub deny: Vec<String>,
}

/// Every metric is mechanically computable — no taste-based grading.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Metric {
    /// Slots whose submitted choice differs from `original`. Slot interactions only;
    /// computable from operations alone, without compiling.
    TokenEdits,
    /// Syntactic `.clone()` / `.to_owned()` occurrences in user-controlled text.
    CloneCount,
    ExplicitLoops,
    MutBindings,
    UnsafeBlocks,
    ClippyWarningCount,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Scoring {
    pub primary: Metric,
    #[serde(default)]
    pub secondary: Vec<Metric>,
    /// Rank thresholds: met when computed metric <= value, all entries at once.
    pub fluent: BTreeMap<Metric, u32>,
    pub optimal: BTreeMap<Metric, u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SourceInfo {
    /// `"original"` or the upstream project (e.g. `"rustlings"`).
    pub origin: String,
    /// Upstream licence; `None` only when origin is `"original"`.
    pub license: Option<String>,
    pub attribution: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pack {
    pub schema_version: u32,
    pub id: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Pinned Rust toolchain — part of the outcomes cache key.
    pub toolchain: String,
    pub order: Vec<String>,
}

// ---- Submission + evaluation results (shared by app, outcomes sidecar, API) ----

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Submission {
    pub puzzle_id: String,
    pub puzzle_version: u32,
    pub operations: Vec<Operation>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Operation {
    Select { slot_id: String, choice_id: String },
    Arrange { order: Vec<String> },
    Pick { candidate_id: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvalStatus {
    Solved,
    CompileError,
    TestFailure,
    Invalid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rank {
    Solved,
    Fluent,
    Optimal,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EvalResult {
    pub status: EvalStatus,
    /// `Some` iff status is `Solved`.
    pub rank: Option<Rank>,
    pub metrics: BTreeMap<Metric, u32>,
    pub diagnostics: Vec<Diagnostic>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Diagnostic {
    /// App-facing class, e.g. `"borrow_conflict"`, `"move_error"`.
    pub category: String,
    /// Puzzle-language message, not raw compiler prose.
    pub message: String,
    #[serde(default)]
    pub slot_ids: Vec<String>,
    /// Underlying rustc code (e.g. `"E0502"`) for the "Compiler details" disclosure.
    #[serde(default)]
    pub rust_code: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Outcomes {
    pub schema_version: u32,
    pub puzzle_id: String,
    pub puzzle_version: u32,
    pub toolchain: String,
    /// Key: SHA-256 hex of the canonical operations JSON (see [`crate::ops::ops_hash`]).
    pub outcomes: BTreeMap<String, EvalResult>,
}
