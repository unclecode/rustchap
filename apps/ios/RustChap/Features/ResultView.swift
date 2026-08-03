import SwiftUI

struct ResultView: View {
    let loaded: ContentStore.LoadedPuzzle
    let result: EvalResult
    let nextPuzzleId: String?
    let onRetry: () -> Void
    let onNext: (String) -> Void

    @State private var showExplanation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon)
                            .font(.title)
                            .foregroundStyle(statusColor)
                        VStack(alignment: .leading) {
                            Text(statusTitle).font(.headline)
                            if let rank = result.rank {
                                Text(rankLabel(rank))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if result.status == .solved, !result.metrics.isEmpty {
                    Section("Score") {
                        ForEach(result.metrics.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                            HStack {
                                Text(name.replacingOccurrences(of: "_", with: " "))
                                Spacer()
                                Text("\(value)")
                                    .monospacedDigit()
                                if let best = loaded.puzzle.scoring.optimal[name] {
                                    Text("· best \(best)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                        }
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
                    }
                }
            }
            .navigationTitle(loaded.puzzle.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

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

    private func rankLabel(_ rank: EvalResult.Rank) -> String {
        switch rank {
        case .solved: "Solved — a cleaner solution exists"
        case .fluent: "Fluent — one step from optimal"
        case .optimal: "Optimal — the best known solution"
        }
    }
}
