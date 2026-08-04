//! Cross-field invariants JSON Schema cannot express, plus submission-space
//! enumeration for the outcomes sidecar. The linter is the primary consumer.

use std::collections::BTreeSet;

use thiserror::Error;

use crate::template::{is_valid_slot_id, parse_template, slot_ids};
use crate::types::{Interaction, LessonSection, Metric, Operation, Puzzle};

/// Every legal submission for a puzzle is precomputed into its outcomes sidecar;
/// the linter rejects puzzles whose space exceeds this. Also healthy design
/// pressure: a puzzle with thousands of combinations is guessable, not learnable.
pub const MAX_SUBMISSION_SPACE: u128 = 512;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ValidationError {
    #[error("schema_version must be 1, got {0}")]
    SchemaVersion(u32),
    #[error("invalid puzzle id {0:?} (want <track>.<nnn>, e.g. move-or-borrow.001)")]
    PuzzleId(String),
    #[error("puzzle id {id:?} does not belong to track {track:?}")]
    IdTrackMismatch { id: String, track: String },
    #[error("difficulty must be 1..=5, got {0}")]
    Difficulty(u8),
    #[error("template error: {0}")]
    Template(#[from] crate::template::TemplateError),
    #[error("interaction requires a template but none is present")]
    MissingTemplate,
    #[error("interaction takes no template but one is present")]
    UnexpectedTemplate,
    #[error("duplicate id {0:?}")]
    DuplicateId(String),
    #[error("invalid id {0:?} (want [a-z][a-z0-9_]*)")]
    InvalidId(String),
    #[error("template marker {0:?} has no slot definition")]
    MarkerWithoutSlot(String),
    #[error("slot {0:?} never appears in the template")]
    SlotWithoutMarker(String),
    #[error("slot {0:?} needs at least 2 choices")]
    TooFewChoices(String),
    #[error("slot {slot:?} has duplicate choice text {text:?}")]
    DuplicateChoiceText { slot: String, text: String },
    #[error("minimal-edit slot {0:?} has no original token")]
    MinimalEditNeedsOriginal(String),
    #[error(
        "minimal-edit slot {0:?}: original is not among its choices, so 'keep' is inexpressible"
    )]
    OriginalNotInChoices(String),
    #[error("need at least 2 {0}")]
    TooFew(&'static str),
    #[error("evaluation.metrics is empty or has duplicates")]
    BadMetricList,
    #[error("scoring references metric {0:?} not listed in evaluation.metrics")]
    UnlistedMetric(&'static str),
    #[error("token_edits is only computable for slot interactions")]
    TokenEditsWithoutSlots,
    #[error("source.license is required unless origin is \"original\"")]
    MissingLicense,
    #[error("submission space {0} exceeds the maximum of {MAX_SUBMISSION_SPACE}")]
    SpaceTooLarge(u128),
    #[error("lesson puzzles must not define evaluation or scoring")]
    LessonWithEvaluation,
    #[error("non-lesson puzzles must define both evaluation and scoring")]
    MissingEvaluation,
    #[error("lesson section has empty {0}")]
    EmptyLessonSection(&'static str),
}

/// All invariant violations at once (the linter reports them together).
pub fn validate_puzzle(puzzle: &Puzzle) -> Result<(), Vec<ValidationError>> {
    let mut errors = Vec::new();

    if puzzle.schema_version != 1 {
        errors.push(ValidationError::SchemaVersion(puzzle.schema_version));
    }
    match puzzle.id.rsplit_once('.') {
        Some((track, num))
            if !track.is_empty()
                && track
                    .chars()
                    .all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'))
                && num.len() == 3
                && num.chars().all(|c| c.is_ascii_digit()) =>
        {
            if track != puzzle.track {
                errors.push(ValidationError::IdTrackMismatch {
                    id: puzzle.id.clone(),
                    track: puzzle.track.clone(),
                });
            }
        }
        _ => errors.push(ValidationError::PuzzleId(puzzle.id.clone())),
    }
    if !(1..=5).contains(&puzzle.difficulty) {
        errors.push(ValidationError::Difficulty(puzzle.difficulty));
    }

    validate_interaction(puzzle, &mut errors);
    validate_scoring(puzzle, &mut errors);

    if puzzle.source.origin != "original" && puzzle.source.license.is_none() {
        errors.push(ValidationError::MissingLicense);
    }

    if errors.is_empty() {
        let space = submission_space(puzzle);
        if space > MAX_SUBMISSION_SPACE {
            errors.push(ValidationError::SpaceTooLarge(space));
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn validate_interaction(puzzle: &Puzzle, errors: &mut Vec<ValidationError>) {
    match &puzzle.interaction {
        Interaction::SlotSelection { slots } | Interaction::MinimalEdit { slots } => {
            let minimal_edit = matches!(puzzle.interaction, Interaction::MinimalEdit { .. });
            if slots.is_empty() {
                errors.push(ValidationError::TooFew("slots"));
            }
            check_unique_ids(slots.iter().map(|s| s.id.as_str()), errors);
            for slot in slots {
                if !is_valid_slot_id(&slot.id) {
                    errors.push(ValidationError::InvalidId(slot.id.clone()));
                }
                if slot.choices.len() < 2 {
                    errors.push(ValidationError::TooFewChoices(slot.id.clone()));
                }
                check_unique_ids(slot.choices.iter().map(|c| c.id.as_str()), errors);
                let mut texts = BTreeSet::new();
                for choice in &slot.choices {
                    if !texts.insert(choice.text.as_str()) {
                        errors.push(ValidationError::DuplicateChoiceText {
                            slot: slot.id.clone(),
                            text: choice.text.clone(),
                        });
                    }
                }
                if minimal_edit {
                    match &slot.original {
                        None => {
                            errors.push(ValidationError::MinimalEditNeedsOriginal(slot.id.clone()))
                        }
                        Some(original) if !slot.choices.iter().any(|c| c.text == *original) => {
                            errors.push(ValidationError::OriginalNotInChoices(slot.id.clone()));
                        }
                        Some(_) => {}
                    }
                }
            }
            match puzzle.template.as_deref() {
                None => errors.push(ValidationError::MissingTemplate),
                Some(template) => match parse_template(template) {
                    Err(e) => errors.push(e.into()),
                    Ok(segments) => {
                        let markers: BTreeSet<&str> = slot_ids(&segments).into_iter().collect();
                        let defined: BTreeSet<&str> = slots.iter().map(|s| s.id.as_str()).collect();
                        for marker in markers.difference(&defined) {
                            errors.push(ValidationError::MarkerWithoutSlot(marker.to_string()));
                        }
                        for slot in defined.difference(&markers) {
                            errors.push(ValidationError::SlotWithoutMarker(slot.to_string()));
                        }
                    }
                },
            }
        }
        Interaction::BlockArrangement { blocks, .. } => {
            if puzzle.template.is_some() {
                errors.push(ValidationError::UnexpectedTemplate);
            }
            if blocks.len() < 2 {
                errors.push(ValidationError::TooFew("blocks"));
            }
            check_unique_ids(blocks.iter().map(|b| b.id.as_str()), errors);
            for block in blocks {
                if !is_valid_slot_id(&block.id) {
                    errors.push(ValidationError::InvalidId(block.id.clone()));
                }
            }
        }
        Interaction::BestSolution { candidates } => {
            if puzzle.template.is_some() {
                errors.push(ValidationError::UnexpectedTemplate);
            }
            if candidates.len() < 2 {
                errors.push(ValidationError::TooFew("candidates"));
            }
            check_unique_ids(candidates.iter().map(|c| c.id.as_str()), errors);
        }
        Interaction::Lesson { sections } => {
            if puzzle.template.is_some() {
                errors.push(ValidationError::UnexpectedTemplate);
            }
            if sections.is_empty() {
                errors.push(ValidationError::TooFew("sections"));
            }
            for section in sections {
                match section {
                    LessonSection::Prose { text } if text.trim().is_empty() => {
                        errors.push(ValidationError::EmptyLessonSection("prose"));
                    }
                    LessonSection::Code { code, .. } if code.trim().is_empty() => {
                        errors.push(ValidationError::EmptyLessonSection("code"));
                    }
                    _ => {}
                }
            }
        }
    }
}

fn validate_scoring(puzzle: &Puzzle, errors: &mut Vec<ValidationError>) {
    let is_lesson = matches!(puzzle.interaction, Interaction::Lesson { .. });
    let (evaluation, scoring) = match (&puzzle.evaluation, &puzzle.scoring, is_lesson) {
        (None, None, true) => return,
        (_, _, true) => {
            errors.push(ValidationError::LessonWithEvaluation);
            return;
        }
        (Some(evaluation), Some(scoring), false) => (evaluation, scoring),
        _ => {
            errors.push(ValidationError::MissingEvaluation);
            return;
        }
    };

    let metrics = &evaluation.metrics;
    let unique: BTreeSet<&Metric> = metrics.iter().collect();
    if metrics.is_empty() || unique.len() != metrics.len() {
        errors.push(ValidationError::BadMetricList);
    }
    let mut referenced: Vec<Metric> = vec![scoring.primary];
    referenced.extend(scoring.secondary.iter().copied());
    referenced.extend(scoring.fluent.keys().copied());
    referenced.extend(scoring.optimal.keys().copied());
    for metric in &referenced {
        if !unique.contains(metric) {
            errors.push(ValidationError::UnlistedMetric("scoring"));
            break;
        }
    }
    if referenced.contains(&Metric::TokenEdits) && puzzle.interaction.slots().is_none() {
        errors.push(ValidationError::TokenEditsWithoutSlots);
    }
}

fn check_unique_ids<'a>(ids: impl Iterator<Item = &'a str>, errors: &mut Vec<ValidationError>) {
    let mut seen = BTreeSet::new();
    for id in ids {
        if !seen.insert(id) {
            errors.push(ValidationError::DuplicateId(id.to_string()));
        }
    }
}

/// Number of distinct legal submissions: product of choice counts (slot
/// interactions), blocks! (arrangement), or candidate count (best-solution).
pub fn submission_space(puzzle: &Puzzle) -> u128 {
    match &puzzle.interaction {
        Interaction::SlotSelection { slots } | Interaction::MinimalEdit { slots } => {
            slots.iter().map(|s| s.choices.len() as u128).product()
        }
        Interaction::BlockArrangement { blocks, .. } => (1..=blocks.len() as u128).product(),
        Interaction::BestSolution { candidates } => candidates.len() as u128,
        Interaction::Lesson { .. } => 0,
    }
}

/// Every legal submission, in deterministic order — what the linter iterates to
/// generate the outcomes sidecar. Call only after [`validate_puzzle`] passed
/// (the space is then known to be small).
pub fn enumerate_submissions(puzzle: &Puzzle) -> Vec<Vec<Operation>> {
    match &puzzle.interaction {
        Interaction::SlotSelection { slots } | Interaction::MinimalEdit { slots } => {
            let mut result = vec![Vec::new()];
            for slot in slots {
                result = result
                    .into_iter()
                    .flat_map(|prefix| {
                        slot.choices.iter().map(move |choice| {
                            let mut ops = prefix.clone();
                            ops.push(Operation::Select {
                                slot_id: slot.id.clone(),
                                choice_id: choice.id.clone(),
                            });
                            ops
                        })
                    })
                    .collect();
            }
            result
        }
        Interaction::BlockArrangement { blocks, .. } => {
            let ids: Vec<String> = blocks.iter().map(|b| b.id.clone()).collect();
            permutations(&ids)
                .into_iter()
                .map(|order| vec![Operation::Arrange { order }])
                .collect()
        }
        Interaction::BestSolution { candidates } => candidates
            .iter()
            .map(|c| {
                vec![Operation::Pick {
                    candidate_id: c.id.clone(),
                }]
            })
            .collect(),
        Interaction::Lesson { .. } => Vec::new(),
    }
}

fn permutations(items: &[String]) -> Vec<Vec<String>> {
    if items.is_empty() {
        return vec![Vec::new()];
    }
    let mut result = Vec::new();
    for (i, item) in items.iter().enumerate() {
        let mut rest: Vec<String> = items.to_vec();
        rest.remove(i);
        for mut tail in permutations(&rest) {
            tail.insert(0, item.clone());
            result.push(tail);
        }
    }
    result
}
