import SwiftUI

struct ResultView: View {
    let loaded: ContentStore.LoadedPuzzle
    let result: EvalResult
    let via: EvaluatedVia
    let nextPuzzleId: String?
    let onRetry: () -> Void
    let onNext: (String) -> Void
    let onDeckComplete: () -> Void

    @State private var showExplanation = false

    private var scoring: Scoring { loaded.puzzle.scoring }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon)
                                .font(.title2)
                                .foregroundStyle(statusColor)
                            Text(statusTitle)
                                .font(.headline)
                        }
                        if result.status == .solved, let rank = result.rank {
                            RankLadder(achieved: rank)
                            if let goal = nextRankGoal(after: rank) {
                                Text(goal)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Label(viaText, systemImage: viaIcon)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                if result.status == .solved {
                    Section("Score") {
                        scoreRow(label: "You", values: result.metrics, emphasized: false)
                        scoreRow(label: "Best known", values: scoring.optimal, emphasized: true)
                    }
                }

                if !result.diagnostics.isEmpty {
                    Section("What went wrong") {
                        ForEach(Array(result.diagnostics.enumerated()), id: \.offset) { _, diag in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(diag.category.replacingOccurrences(of: "_", with: " "))
                                        .font(.caption.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.red.opacity(0.15), in: Capsule())
                                    if let code = diag.rustCode {
                                        Text(code)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(diag.message).font(.footnote)
                            }
                        }
                    }
                }

                if result.status == .solved {
                    Section {
                        DisclosureGroup("Explanation", isExpanded: $showExplanation) {
                            Text(loaded.puzzle.explanation).font(.footnote)
                        }
                    }
                }

                Section {
                    Button(action: onRetry) {
                        Text(result.rank == .optimal ? "Play again" : "Try for a better score")
                            .frame(maxWidth: .infinity)
                    }
                    if result.status == .solved, let nextPuzzleId {
                        Button { onNext(nextPuzzleId) } label: {
                            Text("Next puzzle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if result.status == .solved {
                        Button(action: onDeckComplete) {
                            Text("Deck finished — back to the decks")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(loaded.puzzle.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }

    // MARK: - Score

    private func scoreRow(label: String, values: [String: Int], emphasized: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .frame(width: 92, alignment: .leading)
            Text(profileText(values))
                .font(.callout.monospacedDigit())
                .fontWeight(emphasized ? .semibold : .regular)
        }
    }

    /// "1 clone · 1 edit" — whole-solution profile in a fixed metric order.
    private func profileText(_ values: [String: Int]) -> String {
        let parts = scoring.displayOrder.compactMap { metric -> String? in
            guard let value = values[metric] else { return nil }
            // Hide a Clippy metric that is 0 on both sides — pure noise.
            if metric == "clippy_warning_count", values[metric] == 0,
               result.metrics[metric] ?? 0 == 0, scoring.optimal[metric] ?? 0 == 0 {
                return nil
            }
            return Self.phrase(metric: metric, value: value)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    static func phrase(metric: String, value: Int) -> String {
        let noun: (singular: String, plural: String) = switch metric {
        case "clone_count": ("clone", "clones")
        case "token_edits": ("edit", "edits")
        case "clippy_warning_count": ("Clippy warning", "Clippy warnings")
        case "explicit_loops": ("loop", "loops")
        case "mut_bindings": ("mut binding", "mut bindings")
        case "unsafe_blocks": ("unsafe block", "unsafe blocks")
        default: (metric, metric)
        }
        return "\(value) \(value == 1 ? noun.singular : noun.plural)"
    }

    private func nextRankGoal(after rank: EvalResult.Rank) -> String? {
        let target: (name: String, thresholds: [String: Int])? = switch rank {
        case .solved: scoring.fluent.isEmpty ? nil : ("Fluent", scoring.fluent)
        case .fluent: scoring.optimal.isEmpty ? nil : ("Optimal", scoring.optimal)
        case .optimal: nil
        }
        guard let target else { return nil }
        let needs = scoring.displayOrder.compactMap { metric -> String? in
            guard let max = target.thresholds[metric] else { return nil }
            let phrase = Self.phrase(metric: metric, value: max)
            return max == 0 ? phrase : "≤ " + phrase
        }
        guard !needs.isEmpty else { return nil }
        return "\(target.name) needs: \(needs.joined(separator: " · "))"
    }

    // MARK: - Evaluation source

    private var viaText: String {
        switch via {
        case .serverCached: "Server verdict · precomputed"
        case .serverCompiled: "Server verdict · compiled live"
        case .onDevice: "On-device verdict · offline"
        }
    }

    private var viaIcon: String {
        switch via {
        case .serverCached: "cloud"
        case .serverCompiled: "cloud.bolt"
        case .onDevice: "iphone"
        }
    }

    // MARK: - Status

    private var statusTitle: String {
        switch result.status {
        case .solved: "Solved"
        case .compileError: "Doesn't compile"
        case .testFailure: "Compiles, but the tests fail"
        case .invalid: "Invalid submission"
        }
    }

    private var statusIcon: String {
        switch result.status {
        case .solved:
            result.rank == .optimal ? "star.circle.fill" : "checkmark.circle.fill"
        case .compileError: "xmark.octagon.fill"
        case .testFailure: "exclamationmark.triangle.fill"
        case .invalid: "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .solved: result.rank == .optimal ? .yellow : .green
        case .compileError: .red
        case .testFailure: .orange
        case .invalid: .gray
        }
    }
}

/// Solved ──── Fluent ──── Optimal, achieved steps filled. Makes the rank
/// order visible instead of relying on vocabulary.
private struct RankLadder: View {
    let achieved: EvalResult.Rank

    private let steps: [(rank: EvalResult.Rank, label: String)] = [
        (.solved, "Solved"), (.fluent, "Fluent"), (.optimal, "Optimal"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(reached(step.rank) ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 16)
                }
                VStack(spacing: 4) {
                    Image(systemName: reached(step.rank)
                        ? (step.rank == .optimal ? "star.circle.fill" : "checkmark.circle.fill")
                        : "circle")
                        .foregroundStyle(reached(step.rank) ? Color.accentColor : Color.secondary.opacity(0.4))
                    Text(step.label)
                        .font(.caption2)
                        .fontWeight(step.rank == achieved ? .semibold : .regular)
                        .foregroundStyle(reached(step.rank) ? .primary : .secondary)
                }
            }
        }
    }

    private func reached(_ rank: EvalResult.Rank) -> Bool {
        rank <= achieved
    }
}
