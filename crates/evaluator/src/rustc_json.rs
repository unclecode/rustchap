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
                message: sanitize_paths(&d.message),
                slot_ids,
                rust_code: d.code.as_ref().map(|c| c.code.clone()),
            }
        })
        .collect()
}

/// Strip the compile directory out of a diagnostic message.
///
/// rustc names closures and async blocks by their source location, e.g.
/// `{async closure body@/var/folders/.../.tmpAbC123/main.rs:4:41: 6:6}`. Each
/// run compiles in a FRESH temp directory, so that text differs every time and
/// the puzzle's stored outcomes can never match a recompile: the linter reports
/// it stale forever, on every machine. Replace the directory with `<src>` so the
/// message stays useful and stays stable.
fn sanitize_paths(message: &str) -> String {
    let mut out = String::with_capacity(message.len());
    let mut rest = message;
    while let Some(at) = rest.find('/') {
        let (head, tail) = rest.split_at(at);
        out.push_str(head);
        // a path runs until whitespace, a closing brace, or a quote
        let end = tail
            .find(|c: char| c.is_whitespace() || c == '}' || c == '`' || c == '\'')
            .unwrap_or(tail.len());
        let (path, after) = tail.split_at(end);
        // Drop the directory entirely rather than replacing it. rustc prints a
        // RELATIVE path on macOS ("main.rs:12:32") and an ABSOLUTE one on Linux,
        // so keeping any prefix makes the two platforms disagree and CI reports
        // outcomes stale that are fine locally.
        match path.rfind('/') {
            Some(slash) => out.push_str(&path[slash + 1..]),
            None => out.push_str(path),
        }
        rest = after;
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod sanitize_tests {
    use super::sanitize_paths;

    #[test]
    fn strips_the_temp_directory_but_keeps_the_file_and_position() {
        let a = sanitize_paths(
            "`{async closure body@/var/folders/z7/x/.tmp7xzABB/main.rs:4:41: 6:6}` doesn't implement `Debug`");
        let b = sanitize_paths(
            "`{async closure body@/var/folders/z7/x/.tmpCc3v7p/main.rs:4:41: 6:6}` doesn't implement `Debug`");
        assert_eq!(a, b, "two runs must produce the same message");
        assert!(a.contains("main.rs:4:41"), "position is still useful: {a}");
        assert!(!a.contains(".tmp"), "temp dir is gone: {a}");
        assert!(!a.contains('/'), "no directory survives: {a}");
    }

    #[test]
    fn relative_and_absolute_paths_agree() {
        // macOS prints the file relative, Linux prints it absolute. Both must
        // reduce to the same text or CI disagrees with the developer machine.
        let mac = sanitize_paths("`{closure@main.rs:12:32}` does not implement `Fn`");
        let linux = sanitize_paths("`{closure@/tmp/.tmpQ9/main.rs:12:32}` does not implement `Fn`");
        assert_eq!(mac, linux);
    }

    #[test]
    fn leaves_ordinary_messages_alone() {
        let m = "cannot borrow `x` as mutable more than once at a time";
        assert_eq!(sanitize_paths(m), m);
    }
}
