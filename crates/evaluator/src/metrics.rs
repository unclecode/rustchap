//! Syntactic metric counting over the user-controlled text of a reconstruction.
//! Deliberately simple and deterministic: these numbers must be reproducible on
//! any platform from the puzzle JSON alone. Fuzzier qualities (allocations)
//! ride on Clippy lints instead, per the scoring model.

use std::collections::BTreeMap;

use puzzle_schema::{Metric, Operation, Puzzle, Reconstruction, token_edits};

/// Compute every metric in `wanted` except `ClippyWarningCount` (the caller
/// merges that in after running clippy).
pub fn compute(
    puzzle: &Puzzle,
    operations: &[Operation],
    reconstruction: &Reconstruction,
    wanted: &[Metric],
) -> BTreeMap<Metric, u32> {
    let user_text = reconstruction.user_text();
    let mut out = BTreeMap::new();
    for metric in wanted {
        let value = match metric {
            Metric::TokenEdits => token_edits(puzzle, operations).unwrap_or(0),
            Metric::CloneCount => {
                count_substring(&user_text, ".clone()") + count_substring(&user_text, ".to_owned()")
            }
            Metric::ExplicitLoops => {
                count_word(&user_text, "for")
                    + count_word(&user_text, "while")
                    + count_word(&user_text, "loop")
            }
            Metric::MutBindings => count_word(&user_text, "mut"),
            Metric::UnsafeBlocks => count_word(&user_text, "unsafe"),
            Metric::ClippyWarningCount => continue,
        };
        out.insert(*metric, value);
    }
    out
}

fn count_substring(haystack: &str, needle: &str) -> u32 {
    haystack.matches(needle).count() as u32
}

/// Count whole-word occurrences: `needle` delimited by non-identifier chars,
/// so "for" never matches inside "performance".
fn count_word(haystack: &str, needle: &str) -> u32 {
    let is_ident = |c: char| c.is_ascii_alphanumeric() || c == '_';
    let mut count = 0;
    let mut word_start = None::<usize>;
    for (i, c) in haystack.char_indices() {
        if is_ident(c) {
            word_start.get_or_insert(i);
        } else if let Some(start) = word_start.take()
            && &haystack[start..i] == needle
        {
            count += 1;
        }
    }
    if let Some(start) = word_start
        && &haystack[start..] == needle
    {
        count += 1;
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn word_counting_respects_boundaries() {
        assert_eq!(count_word("for x in performance { for }", "for"), 2);
        assert_eq!(count_word("let mut a = &mut b;", "mut"), 2);
        assert_eq!(count_word("formula", "for"), 0);
        assert_eq!(count_word("for", "for"), 1);
    }

    #[test]
    fn clone_counting_matches_calls_only() {
        assert_eq!(
            count_substring("a.clone(); b.to_owned(); cloned()", ".clone()"),
            1
        );
    }
}
