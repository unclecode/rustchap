// The cost language: one letter per metric ("0C·2E"), a live counter that
// mirrors crates/evaluator/src/metrics.rs, and the letter legend.
// Live numbers are a PREVIEW computed from the current picks; the outcomes
// table at Run stays the only truth. Any divergence from metrics.rs counting
// is a bug on this side.

import SwiftUI

struct CostMetric {
    let key: String
    let letter: String
    let name: String
    let detail: String
    let legendColor: Color
    /// False when only the compiler can produce the number (Clippy).
    let live: Bool
}

enum CostLanguage {
    static let all: [CostMetric] = [
        CostMetric(
            key: "token_edits", letter: "E", name: "Edits",
            detail: "Tokens you changed from the original. Counted in every slot puzzle.",
            legendColor: .blue, live: true),
        CostMetric(
            key: "clone_count", letter: "C", name: "Clones",
            detail: "Explicit copies: .clone(), .to_owned(), .to_vec(), .cloned().",
            legendColor: .orange, live: true),
        CostMetric(
            key: "clippy_warning_count", letter: "W", name: "Warnings",
            detail: "Clippy lint hits. The compiler verifies these when you Run.",
            legendColor: .purple, live: false),
        CostMetric(
            key: "mut_bindings", letter: "M", name: "Mut bindings",
            detail: "Mutable state you declare with mut.",
            legendColor: .pink, live: true),
        CostMetric(
            key: "explicit_loops", letter: "L", name: "Loops",
            detail: "Explicit for, while, and loop blocks.",
            legendColor: .teal, live: true),
        CostMetric(
            key: "unsafe_blocks", letter: "U", name: "Unsafe blocks",
            detail: "unsafe { } regions you sign for.",
            legendColor: .red, live: true),
    ]

    static func metric(_ key: String) -> CostMetric? {
        all.first { $0.key == key }
    }

    static func letter(_ key: String) -> String {
        metric(key)?.letter ?? String(key.prefix(1)).uppercased()
    }

    /// Threshold keys in display order: scoring order first, leftovers appended.
    /// A zero Clippy budget is the norm ("stay clean"), not a number worth
    /// space in the chip — it is dropped from notation.
    static func orderedKeys(_ values: [String: Int], order: [String]) -> [String] {
        var keys = order.filter { values[$0] != nil }
        for key in values.keys.sorted() where !keys.contains(key) {
            keys.append(key)
        }
        return keys.filter { !($0 == "clippy_warning_count" && values[$0] == 0) }
    }

    /// "0C·2E" — the game's compact cost notation.
    static func notation(_ values: [String: Int], order: [String]) -> String {
        orderedKeys(values, order: order)
            .map { "\(values[$0] ?? 0)\(letter($0))" }
            .joined(separator: "·")
    }

    // MARK: - Live counting (mirror of metrics.rs)

    struct LiveCost {
        /// Metric key → current count over the player's picks.
        let counts: [String: Int]
        /// Every input chosen (all slots / a candidate picked).
        let complete: Bool
    }

    static func liveCost(
        puzzle: Puzzle,
        selections: [String: String],
        blockOrder: [Block],
        chosenCandidate: String?
    ) -> LiveCost {
        var texts: [String] = []
        var complete = true
        var edits = 0

        switch puzzle.interaction {
        case .slotSelection(let slots), .minimalEdit(let slots):
            for slot in slots {
                guard let choiceId = selections[slot.id],
                      let choice = slot.choices.first(where: { $0.id == choiceId })
                else {
                    complete = false
                    continue
                }
                texts.append(choice.text)
                // Blank original counts every assignment as one edit (metrics.rs).
                if slot.original == nil || choice.text != slot.original {
                    edits += 1
                }
            }
        case .blockArrangement(_, let blocks, _):
            texts = blocks.map(\.text)
        case .bestSolution(let candidates):
            if let chosen = candidates.first(where: { $0.id == chosenCandidate }) {
                texts.append(chosen.code)
            } else {
                complete = false
            }
        case .lesson:
            return LiveCost(counts: [:], complete: true)
        }

        let userText = texts.joined(separator: "\n")
        var counts: [String: Int] = ["token_edits": edits]
        counts["clone_count"] = [".clone()", ".to_owned()", ".to_vec()", ".cloned()"]
            .map { countSubstring(userText, $0) }
            .reduce(0, +)
        counts["explicit_loops"] = countWord(userText, "for")
            + countWord(userText, "while") + countWord(userText, "loop")
        counts["mut_bindings"] = countWord(userText, "mut")
        counts["unsafe_blocks"] = countWord(userText, "unsafe")
        return LiveCost(counts: counts, complete: complete)
    }

    private static func countSubstring(_ haystack: String, _ needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: search) {
            count += 1
            search = found.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Whole-word counting: needle delimited by non-identifier characters,
    /// so "for" never matches inside "performance" (metrics.rs semantics).
    private static func countWord(_ haystack: String, _ needle: String) -> Int {
        var count = 0
        var word = ""
        for char in haystack {
            if char.isASCII && (char.isLetter || char.isNumber || char == "_") {
                word.append(char)
            } else {
                if word == needle { count += 1 }
                word = ""
            }
        }
        if word == needle { count += 1 }
        return count
    }
}
