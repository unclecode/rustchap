// The scoreboard: overall standing + per-deck progress, one tap from any
// screen (chart toolbar button, same always-there pattern as the tutor).
// The profile stays for identity/settings; THIS is where progress lives.

import SwiftData
import SwiftUI

struct ScoreboardSheet: View {
    @Environment(ContentStore.self) private var store
    @Query private var progress: [PuzzleProgressRecord]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        statTile(
                            value: "\(totalSolved)/\(totalNodes)",
                            label: "Solved",
                            color: .green)
                        statTile(
                            value: "\(totalOptimal)",
                            label: "★ Optimal",
                            color: .yellow)
                        statTile(
                            value: "\(totalAttempts)",
                            label: "Attempts",
                            color: .secondary)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                ForEach(store.visibleLevels) { level in
                    Section(level.title) {
                        ForEach(store.packs(in: level.id).filter { !$0.puzzles.isEmpty }) { deck in
                            deckRow(deck)
                        }
                    }
                }
            }
            .navigationTitle("Scoreboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Pieces

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func deckRow(_ deck: ContentStore.LoadedPack) -> some View {
        let accent = DeckListView.accentColor(deck.pack.accent)
        let solved = solvedCount(deck)
        let stars = optimalCount(deck)
        let total = deck.puzzles.count
        return HStack(spacing: 12) {
            Image(systemName: deck.pack.icon ?? "square.stack.3d.up.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(deck.pack.title)
                    .font(.subheadline.weight(.medium))
                ProgressView(value: Double(solved), total: Double(total))
                    .tint(solved == total ? .green : accent)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(solved)/\(total)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(solved == total ? .green : .secondary)
                if stars > 0 {
                    Label("\(stars)", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Numbers

    private func record(for puzzleId: String) -> PuzzleProgressRecord? {
        progress.first { $0.puzzleId == puzzleId }
    }

    private func solvedCount(_ deck: ContentStore.LoadedPack) -> Int {
        deck.puzzles.filter { record(for: $0.id)?.solved == true }.count
    }

    private func optimalCount(_ deck: ContentStore.LoadedPack) -> Int {
        deck.puzzles.filter { record(for: $0.id)?.bestRank == .optimal }.count
    }

    private var totalNodes: Int { store.packs.reduce(0) { $0 + $1.puzzles.count } }
    private var totalSolved: Int { progress.filter(\.solved).count }
    private var totalOptimal: Int { progress.filter { $0.bestRank == .optimal }.count }
    private var totalAttempts: Int { progress.reduce(0) { $0 + $1.attemptCount } }
}

// MARK: - Global entry point

/// Chart button in the toolbar; the scoreboard drawer is one tap away on
/// every screen that applies this. `--scoreboard` opens it for screenshots.
struct ScoreboardButton: ViewModifier {
    @State private var showScoreboard = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScoreboard = true
                    } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                    .accessibilityLabel("Scoreboard")
                }
            }
            .sheet(isPresented: $showScoreboard) {
                ScoreboardSheet()
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--scoreboard") {
                    showScoreboard = true
                }
            }
    }
}

extension View {
    func scoreboardButton() -> some View {
        modifier(ScoreboardButton())
    }
}
