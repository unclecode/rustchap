// Offline evaluation against the linter-generated outcomes sidecar.
//
// The hash MUST byte-match the Rust implementation (puzzle-schema::ops):
// canonical JSON = compact separators, fixed field order per operation kind,
// select ops sorted by slot_id. Any divergence here silently breaks every
// lookup — see the cross-platform hash test in scripts/verify_ops_hash.swift.

import CryptoKit
import Foundation

enum PuzzleOperation {
    case select(slotId: String, choiceId: String)
    case arrange(order: [String])
    case pick(candidateId: String)
}

enum OpsHash {
    /// Mirror of Rust `normalized_ops_json`: select ops sorted by slot_id
    /// (stable), arrange/pick keep their internal order.
    static func canonicalJSON(_ operations: [PuzzleOperation]) -> String {
        let sorted = operations.enumerated().sorted { lhs, rhs in
            switch (lhs.element, rhs.element) {
            case (.select(let a, _), .select(let b, _)) where a != b:
                a < b
            default:
                lhs.offset < rhs.offset
            }
        }.map(\.element)

        let fragments = sorted.map { op -> String in
            switch op {
            case .select(let slotId, let choiceId):
                #"{"op":"select","slot_id":\#(jsonString(slotId)),"choice_id":\#(jsonString(choiceId))}"#
            case .arrange(let order):
                #"{"op":"arrange","order":[\#(order.map(jsonString).joined(separator: ","))]}"#
            case .pick(let candidateId):
                #"{"op":"pick","candidate_id":\#(jsonString(candidateId))}"#
            }
        }
        return "[" + fragments.joined(separator: ",") + "]"
    }

    static func hash(_ operations: [PuzzleOperation]) -> String {
        let digest = SHA256.hash(data: Data(canonicalJSON(operations).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// serde_json-compatible string escaping (ids are [a-z0-9_], but stay exact).
    private static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case let s where s.value < 0x20:
                out += String(format: "\\u%04x", s.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

struct LocalEvaluator {
    let outcomes: Outcomes

    /// Exact, offline evaluation: the linter already compiled this submission.
    /// nil means the submission is outside the enumerated space (a client bug).
    func evaluate(_ operations: [PuzzleOperation]) -> EvalResult? {
        outcomes.outcomes[OpsHash.hash(operations)]
    }
}
