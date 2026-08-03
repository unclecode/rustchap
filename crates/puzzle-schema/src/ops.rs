//! Canonical form and hashing for submissions — the shared cache key across the
//! app's bundled outcomes, the server's Redis cache, and the linter's sidecar
//! generation. Cache key = `toolchain + puzzle_version + ops_hash`.

use sha2::{Digest, Sha256};

use crate::types::Operation;

/// Canonical operations: `select` ops sorted by `slot_id`; `arrange`/`pick`
/// pass through (their internal order is meaningful). Input order of a slot
/// submission therefore never changes the hash.
pub fn normalize_ops(operations: &[Operation]) -> Vec<Operation> {
    let mut ops = operations.to_vec();
    ops.sort_by(|a, b| match (a, b) {
        (Operation::Select { slot_id: sa, .. }, Operation::Select { slot_id: sb, .. }) => {
            sa.cmp(sb)
        }
        _ => std::cmp::Ordering::Equal,
    });
    ops
}

/// Compact JSON of the canonical operations — the exact string that is hashed.
/// Field order is fixed by the `Operation` type, separators are serde_json's
/// compact defaults; any other implementation must reproduce this byte-for-byte.
pub fn normalized_ops_json(operations: &[Operation]) -> String {
    serde_json::to_string(&normalize_ops(operations)).expect("operations always serialize")
}

/// SHA-256 hex digest of [`normalized_ops_json`] — the key in `outcomes.json`.
pub fn ops_hash(operations: &[Operation]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(normalized_ops_json(operations).as_bytes());
    let digest = hasher.finalize();
    let mut out = String::with_capacity(64);
    for byte in digest {
        use std::fmt::Write;
        write!(out, "{byte:02x}").expect("writing to String cannot fail");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn select(slot: &str, choice: &str) -> Operation {
        Operation::Select {
            slot_id: slot.to_string(),
            choice_id: choice.to_string(),
        }
    }

    #[test]
    fn hash_is_order_independent_for_selects() {
        let a = [select("arg", "c2"), select("param_ty", "t3")];
        let b = [select("param_ty", "t3"), select("arg", "c2")];
        assert_eq!(ops_hash(&a), ops_hash(&b));
    }

    #[test]
    fn hash_distinguishes_choices() {
        let a = [select("arg", "c1")];
        let b = [select("arg", "c2")];
        assert_ne!(ops_hash(&a), ops_hash(&b));
    }

    #[test]
    fn arrange_order_is_meaningful() {
        let a = [Operation::Arrange {
            order: vec!["b1".into(), "b2".into()],
        }];
        let b = [Operation::Arrange {
            order: vec!["b2".into(), "b1".into()],
        }];
        assert_ne!(ops_hash(&a), ops_hash(&b));
    }

    #[test]
    fn canonical_json_shape_is_stable() {
        // This string is a cross-platform contract — if this test breaks, every
        // bundled outcomes.json and cached evaluation is invalidated.
        assert_eq!(
            normalized_ops_json(&[select("arg", "c2")]),
            r#"[{"op":"select","slot_id":"arg","choice_id":"c2"}]"#
        );
    }
}
