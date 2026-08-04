//! Template parsing and source reconstruction — the single implementation shared
//! by the linter, evaluator, and compiler workers. Clients (iOS) reimplement
//! *display* tokenization only, never reconstruction, so answers cannot diverge.
//!
//! A template is plain Rust source containing `⟦slot_id⟧` markers (U+27E6/U+27E7,
//! never legal Rust). A slot id may appear at multiple positions; every occurrence
//! receives the same value on reconstruction.

use std::collections::BTreeMap;

use thiserror::Error;

use crate::types::{Interaction, Operation, Puzzle};

pub const MARKER_OPEN: char = '⟦';
pub const MARKER_CLOSE: char = '⟧';

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Segment {
    Static(String),
    Slot(String),
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum TemplateError {
    #[error("unclosed ⟦ marker at byte offset {0}")]
    Unclosed(usize),
    #[error("unmatched ⟧ at byte offset {0}")]
    Unmatched(usize),
    #[error("nested ⟦ inside marker at byte offset {0}")]
    Nested(usize),
    #[error("invalid slot id {0:?} (want [a-z][a-z0-9_]*)")]
    InvalidSlotId(String),
}

/// Split a template into static text and slot markers.
pub fn parse_template(template: &str) -> Result<Vec<Segment>, TemplateError> {
    let mut segments = Vec::new();
    let mut current = String::new();
    let mut slot: Option<String> = None;

    for (offset, ch) in template.char_indices() {
        match (ch, &mut slot) {
            (MARKER_OPEN, None) => {
                if !current.is_empty() {
                    segments.push(Segment::Static(std::mem::take(&mut current)));
                }
                slot = Some(String::new());
            }
            (MARKER_OPEN, Some(_)) => return Err(TemplateError::Nested(offset)),
            (MARKER_CLOSE, Some(id)) => {
                if !is_valid_slot_id(id) {
                    return Err(TemplateError::InvalidSlotId(id.clone()));
                }
                segments.push(Segment::Slot(std::mem::take(id).to_string()));
                slot = None;
            }
            (MARKER_CLOSE, None) => return Err(TemplateError::Unmatched(offset)),
            (c, Some(id)) => id.push(c),
            (c, None) => current.push(c),
        }
    }
    if slot.is_some() {
        return Err(TemplateError::Unclosed(template.len()));
    }
    if !current.is_empty() {
        segments.push(Segment::Static(current));
    }
    Ok(segments)
}

pub fn is_valid_slot_id(id: &str) -> bool {
    let mut chars = id.chars();
    matches!(chars.next(), Some('a'..='z'))
        && chars.all(|c| matches!(c, 'a'..='z' | '0'..='9' | '_'))
}

/// Slot ids in order of first appearance, deduplicated.
pub fn slot_ids(segments: &[Segment]) -> Vec<&str> {
    let mut seen = Vec::new();
    for seg in segments {
        if let Segment::Slot(id) = seg
            && !seen.contains(&id.as_str())
        {
            seen.push(id.as_str());
        }
    }
    seen
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ReconstructError {
    #[error("template error: {0}")]
    Template(#[from] TemplateError),
    #[error("puzzle has no template but interaction requires one")]
    MissingTemplate,
    #[error("operation kind does not match the puzzle's interaction")]
    WrongOperationKind,
    #[error("duplicate operation for slot {0:?}")]
    DuplicateSlot(String),
    #[error("unknown slot id {0:?}")]
    UnknownSlot(String),
    #[error("unknown choice id {choice:?} for slot {slot:?}")]
    UnknownChoice { slot: String, choice: String },
    #[error("slot {0:?} was not assigned")]
    UnassignedSlot(String),
    #[error("arrange order is not a permutation of the puzzle's block ids")]
    BadArrangement,
    #[error("unknown candidate id {0:?}")]
    UnknownCandidate(String),
    #[error("expected exactly one operation of this kind, got {0}")]
    WrongOperationCount(usize),
    #[error("lesson puzzles have no reconstructable source")]
    NotReconstructable,
}

/// A user-controlled byte range in reconstructed source: which slot / block /
/// candidate produced `start..end`. Lets the evaluator map compiler spans back
/// to the exact token the user touched, and scopes syntactic metric counting.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceSpan {
    pub region_id: String,
    pub start: usize,
    pub end: usize,
}

/// Reconstructed source plus the user-controlled spans inside it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reconstruction {
    pub source: String,
    pub spans: Vec<SourceSpan>,
}

impl Reconstruction {
    /// Region ids whose spans overlap byte range `start..end` (e.g. a rustc
    /// primary span), for diagnostic → token highlighting.
    pub fn regions_overlapping(&self, start: usize, end: usize) -> Vec<&str> {
        self.spans
            .iter()
            .filter(|s| s.start < end && start < s.end)
            .map(|s| s.region_id.as_str())
            .collect()
    }

    /// Concatenated user-controlled text (newline-joined) — the scope over
    /// which syntactic metrics like `clone_count` are counted. For
    /// best-solution puzzles this is the whole candidate: choosing it IS the
    /// user's edit.
    pub fn user_text(&self) -> String {
        let mut out = String::new();
        for span in &self.spans {
            out.push_str(&self.source[span.start..span.end]);
            out.push('\n');
        }
        out
    }
}

/// Reconstruct the complete Rust source a submission denotes.
///
/// Validates the operations against the puzzle's interaction: every slot assigned
/// exactly once via a known choice, an arrangement is a permutation of the block
/// ids, a pick names an existing candidate.
pub fn reconstruct(puzzle: &Puzzle, operations: &[Operation]) -> Result<String, ReconstructError> {
    Ok(reconstruct_with_spans(puzzle, operations)?.source)
}

/// [`reconstruct`], but also reporting where each user-controlled region landed
/// in the output — see [`SourceSpan`].
pub fn reconstruct_with_spans(
    puzzle: &Puzzle,
    operations: &[Operation],
) -> Result<Reconstruction, ReconstructError> {
    match &puzzle.interaction {
        Interaction::SlotSelection { slots } | Interaction::MinimalEdit { slots } => {
            let template = puzzle
                .template
                .as_deref()
                .ok_or(ReconstructError::MissingTemplate)?;
            let segments = parse_template(template)?;

            let mut assigned: BTreeMap<&str, &str> = BTreeMap::new();
            for op in operations {
                let Operation::Select { slot_id, choice_id } = op else {
                    return Err(ReconstructError::WrongOperationKind);
                };
                let slot = slots
                    .iter()
                    .find(|s| s.id == *slot_id)
                    .ok_or_else(|| ReconstructError::UnknownSlot(slot_id.clone()))?;
                let choice = slot
                    .choices
                    .iter()
                    .find(|c| c.id == *choice_id)
                    .ok_or_else(|| ReconstructError::UnknownChoice {
                        slot: slot_id.clone(),
                        choice: choice_id.clone(),
                    })?;
                if assigned.insert(&slot.id, &choice.text).is_some() {
                    return Err(ReconstructError::DuplicateSlot(slot_id.clone()));
                }
            }

            let mut out = String::new();
            let mut spans = Vec::new();
            for seg in &segments {
                match seg {
                    Segment::Static(text) => out.push_str(text),
                    Segment::Slot(id) => {
                        let text = assigned
                            .get(id.as_str())
                            .ok_or_else(|| ReconstructError::UnassignedSlot(id.clone()))?;
                        let start = out.len();
                        out.push_str(text);
                        spans.push(SourceSpan {
                            region_id: id.clone(),
                            start,
                            end: out.len(),
                        });
                    }
                }
            }
            Ok(Reconstruction { source: out, spans })
        }
        Interaction::BlockArrangement {
            fixed_prefix,
            blocks,
            fixed_suffix,
        } => {
            let [Operation::Arrange { order }] = operations else {
                return Err(match operations {
                    [_] => ReconstructError::WrongOperationKind,
                    ops => ReconstructError::WrongOperationCount(ops.len()),
                });
            };
            let mut remaining: Vec<&str> = blocks.iter().map(|b| b.id.as_str()).collect();
            let mut out = fixed_prefix.clone();
            let mut spans = Vec::new();
            for id in order {
                let pos = remaining
                    .iter()
                    .position(|r| r == id)
                    .ok_or(ReconstructError::BadArrangement)?;
                remaining.remove(pos);
                let block = blocks.iter().find(|b| b.id == *id).expect("id verified");
                let start = out.len();
                out.push_str(&block.text);
                spans.push(SourceSpan {
                    region_id: id.clone(),
                    start,
                    end: out.len(),
                });
            }
            if !remaining.is_empty() {
                return Err(ReconstructError::BadArrangement);
            }
            out.push_str(fixed_suffix);
            Ok(Reconstruction { source: out, spans })
        }
        Interaction::BestSolution { candidates } => {
            let [Operation::Pick { candidate_id }] = operations else {
                return Err(match operations {
                    [_] => ReconstructError::WrongOperationKind,
                    ops => ReconstructError::WrongOperationCount(ops.len()),
                });
            };
            let candidate = candidates
                .iter()
                .find(|c| c.id == *candidate_id)
                .ok_or_else(|| ReconstructError::UnknownCandidate(candidate_id.clone()))?;
            Ok(Reconstruction {
                spans: vec![SourceSpan {
                    region_id: candidate.id.clone(),
                    start: 0,
                    end: candidate.code.len(),
                }],
                source: candidate.code.clone(),
            })
        }
        Interaction::Lesson { .. } => Err(ReconstructError::NotReconstructable),
    }
}

/// `token_edits`: slots whose submitted choice text differs from the slot's
/// `original` (a blank original counts every assignment as one edit).
/// Only meaningful for slot-based interactions; returns `None` otherwise.
pub fn token_edits(puzzle: &Puzzle, operations: &[Operation]) -> Option<u32> {
    let slots = puzzle.interaction.slots()?;
    let mut edits = 0;
    for op in operations {
        let Operation::Select { slot_id, choice_id } = op else {
            return None;
        };
        let slot = slots.iter().find(|s| s.id == *slot_id)?;
        let choice = slot.choices.iter().find(|c| c.id == *choice_id)?;
        if slot.original.as_deref() != Some(choice.text.as_str()) {
            edits += 1;
        }
    }
    Some(edits)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_markers_and_static_text() {
        let segments = parse_template("fn f(x: ⟦ty⟧) -> ⟦ty⟧ { ⟦body⟧ }").unwrap();
        assert_eq!(slot_ids(&segments), vec!["ty", "body"]);
        assert_eq!(segments[0], Segment::Static("fn f(x: ".to_string()),);
    }

    #[test]
    fn rejects_malformed_markers() {
        assert_eq!(parse_template("⟦oops"), Err(TemplateError::Unclosed(4 + 3)));
        assert!(matches!(
            parse_template("a⟧b"),
            Err(TemplateError::Unmatched(_))
        ));
        assert!(matches!(
            parse_template("⟦a⟦b⟧⟧"),
            Err(TemplateError::Nested(_))
        ));
        assert!(matches!(
            parse_template("⟦BadId⟧"),
            Err(TemplateError::InvalidSlotId(_))
        ));
    }

    #[test]
    fn spans_track_user_controlled_regions() {
        use crate::types::*;
        let puzzle = Puzzle {
            schema_version: 1,
            id: "t.001".into(),
            version: 1,
            title: "t".into(),
            track: "t".into(),
            concepts: vec!["t".into()],
            difficulty: 1,
            goal: "g".into(),
            template: Some("let x = ⟦val⟧; let y = ⟦val⟧;".into()),
            interaction: Interaction::SlotSelection {
                slots: vec![Slot {
                    id: "val".into(),
                    original: None,
                    label: None,
                    choices: vec![
                        Choice {
                            id: "a".into(),
                            text: "1".into(),
                        },
                        Choice {
                            id: "b".into(),
                            text: "2i64".into(),
                        },
                    ],
                }],
            },
            evaluation: Some(Evaluation {
                tests: vec![],
                clippy: Clippy::default(),
                metrics: vec![Metric::CloneCount],
            }),
            scoring: Some(Scoring {
                primary: Metric::CloneCount,
                secondary: vec![],
                fluent: Default::default(),
                optimal: Default::default(),
            }),
            hints: vec![],
            explanation: String::new(),
            prerequisites: vec![],
            source: SourceInfo {
                origin: "original".into(),
                license: None,
                attribution: None,
            },
        };
        let ops = [Operation::Select {
            slot_id: "val".into(),
            choice_id: "b".into(),
        }];
        let recon = reconstruct_with_spans(&puzzle, &ops).unwrap();
        assert_eq!(recon.source, "let x = 2i64; let y = 2i64;");
        assert_eq!(
            recon.spans.len(),
            2,
            "same slot at two positions → two spans"
        );
        assert_eq!(
            &recon.source[recon.spans[0].start..recon.spans[0].end],
            "2i64"
        );
        assert_eq!(recon.user_text(), "2i64\n2i64\n");
        assert_eq!(recon.regions_overlapping(9, 10), vec!["val"]);
        assert!(recon.regions_overlapping(0, 8).is_empty());
    }
}
