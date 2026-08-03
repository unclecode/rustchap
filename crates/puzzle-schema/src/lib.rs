//! # puzzle-schema
//!
//! The canonical implementation of RustChap's puzzle contract
//! (`schemas/*.schema.json`): serde models, cross-field validation, template
//! parsing, source reconstruction, and submission canonicalization/hashing.
//!
//! Consumers: the puzzle linter (validation + outcomes generation), the
//! evaluator and compiler workers (reconstruction), the API (hashing for the
//! cache key). Clients reimplement *display* tokenization only — reconstruction
//! and hashing must never have a second implementation.

pub mod ops;
pub mod template;
pub mod types;
pub mod validate;

pub use ops::{normalize_ops, normalized_ops_json, ops_hash};
pub use template::{Segment, parse_template, reconstruct, slot_ids, token_edits};
pub use types::*;
pub use validate::{
    MAX_SUBMISSION_SPACE, enumerate_submissions, submission_space, validate_puzzle,
};
