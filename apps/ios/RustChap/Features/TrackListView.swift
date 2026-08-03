// Level 2: the puzzles inside one deck. Locked decks are browsable — the
// list shows what's ahead, but rows only navigate once the deck unlocks.

import SwiftData
import SwiftUI

struct DeckDetailView: View {
    @Environment(ContentStore.self) private var store
    @Query private var progress: [PuzzleProgressRecord]
    let deck: ContentStore.LoadedPack

    private var unlocked: Bool {
        Progression.isUnlocked(
            deckId: deck.id, packs: store.packs,
            solved: Progression.solvedIds(progress)
        )
    }

    private func record(for puzzleId: String) -> PuzzleProgressRecord? {
        progress.first { $0.puzzleId == puzzleId }
    }

    var body: some View {
        List {
            Section {
                ForEach(deck.puzzles) { loaded in
                    if unlocked {
                        NavigationLink(value: Route.puzzle(loaded.id)) {
                            puzzleRow(loaded)
                        }
                    } else {
                        puzzleRow(loaded)
                            .opacity(0.55)
                    }
                }
            } header: {
                if !unlocked {
                    Label("Solve the previous deck to unlock", systemImage: "lock.fill")
                        .font(.footnote)
                }
            } footer: {
                if let description = deck.pack.description {
                    Text(description)
                }
            }
        }
        .navigationTitle(deck.pack.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func puzzleRow(_ loaded: ContentStore.LoadedPuzzle) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loaded.puzzle.title)
                    .font(.headline)
                Text(loaded.puzzle.goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if unlocked {
                progressBadge(for: loaded.id)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func progressBadge(for puzzleId: String) -> some View {
        if let record = record(for: puzzleId), record.solved {
            switch record.bestRank {
            case .optimal:
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(.yellow)
            case .fluent:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.teal)
            default:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else if let record = record(for: puzzleId), record.attemptCount > 0 {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.orange)
        }
    }
}
