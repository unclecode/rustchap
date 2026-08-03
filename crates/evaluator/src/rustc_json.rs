//! Parsing of `rustc --error-format=json` output and its translation into the
//! puzzle's visual language: app-facing categories plus the slot/block ids the
//! error actually touches (via reconstruction spans).

use puzzle_schema::{Diagnostic, Reconstruction};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct RustcDiagnostic {
    pub message: String,
    pub code: Option<RustcCode>,
    pub level: String,
    #[serde(default)]
    pub spans: Vec<RustcSpan>,
}

#[derive(Debug, Deserialize)]
pub struct RustcCode {
    pub code: String,
}

#[derive(Debug, Deserialize)]
pub struct RustcSpan {
    pub byte_start: usize,
    pub byte_end: usize,
    pub is_primary: bool,
}

/// Parse the newline-separated JSON diagnostics rustc/clippy-driver emit on
/// stderr. Non-JSON lines (ICE notes, driver chatter) are skipped.
pub fn parse_stderr(stderr: &str) -> Vec<RustcDiagnostic> {
    stderr
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

/// App-facing category for a rustc error code — the puzzle's visual language.
/// Raw compiler prose stays behind the "Compiler details" disclosure.
pub fn category_for(code: Option<&str>) -> &'static str {
    match code {
        Some("E0382" | "E0383" | "E0505" | "E0507" | "E0508" | "E0509") => "move_error",
        Some("E0499" | "E0500" | "E0501" | "E0502" | "E0503" | "E0506") => "borrow_conflict",
        Some("E0106" | "E0495" | "E0597" | "E0621" | "E0623" | "E0700" | "E0716") => {
            "lifetime_error"
        }
        Some("E0277") => "trait_not_implemented",
        Some("E0308") => "type_mismatch",
        Some("E0425" | "E0433") => "unresolved_name",
        _ => "compile_error",
    }
}

/// Convert error-level rustc diagnostics into puzzle diagnostics, mapping each
/// primary span back to the user-controlled regions it overlaps.
pub fn to_puzzle_diagnostics(
    diags: &[RustcDiagnostic],
    reconstruction: &Reconstruction,
) -> Vec<Diagnostic> {
    diags
        .iter()
        .filter(|d| d.level == "error")
        .map(|d| {
            let mut slot_ids: Vec<String> = d
                .spans
                .iter()
                .filter(|s| s.is_primary)
                .flat_map(|s| reconstruction.regions_overlapping(s.byte_start, s.byte_end))
                .map(str::to_string)
                .collect();
            slot_ids.dedup();
            Diagnostic {
                category: category_for(d.code.as_ref().map(|c| c.code.as_str())).to_string(),
                message: d.message.clone(),
                slot_ids,
                rust_code: d.code.as_ref().map(|c| c.code.clone()),
            }
        })
        .collect()
}
