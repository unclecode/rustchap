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
        .scoreboardButton()
        .tutorButton { .deck(deck, concepts: Array(store.concepts.values)) }
    }

    /// Deck accent from pack.json, matching the home-grid card tile.
    private var accent: Color { DeckListView.accentColor(deck.pack.accent) }

    /// One glyph per interaction type, so the row says how it plays.
    private func typeIcon(_ interaction: Interaction) -> String {
        switch interaction {
        case .slotSelection: "hand.tap.fill"
        case .minimalEdit: "pencil"
        case .blockArrangement: "arrow.up.arrow.down"
        case .bestSolution: "trophy.fill"
        case .lesson: "book.closed.fill"
        }
    }

    private func puzzleRow(_ loaded: ContentStore.LoadedPuzzle) -> some View {
        HStack(spacing: 10) {
            Image(systemName: typeIcon(loaded.puzzle.interaction))
                .font(.subheadline)
                .foregroundStyle(accent)
                .frame(width: 24)
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
        // Keep every separator at the same leading edge — the lesson rows'
        // book icon otherwise pushes their separator further right.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
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
