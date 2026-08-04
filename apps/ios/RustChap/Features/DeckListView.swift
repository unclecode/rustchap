// The home screen: the curriculum as a list of decks (Euclidea's chests, with
// real names). Locked decks stay visible — you can always see the road ahead.
// Two levels only: decks → puzzles.

import SwiftData
import SwiftUI

struct DeckListView: View {
    @Environment(ContentStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Query private var progress: [PuzzleProgressRecord]
    @State private var showProfile = false

    /// The first unlocked, incomplete, non-empty deck — where the player is.
    private var currentDeckId: String? {
        let solved = Progression.solvedIds(progress)
        return store.packs.enumerated().first { index, deck in
            !deck.puzzles.isEmpty
                && Progression.isUnlocked(deckIndex: index, packs: store.packs, solved: solved)
                && !Progression.isComplete(deck, solved: solved)
        }?.element.id
    }

    var body: some View {
        List {
            if let error = store.loadError {
                Text("Content failed to load: \(error)")
                    .foregroundStyle(.red)
            }
            ForEach(Array(store.packs.enumerated()), id: \.element.id) { index, deck in
                deckRow(deck, unlocked: isUnlocked(index))
            }
            Section {
            } footer: {
                Label(
                    store.source == .server
                        ? "Content from server (\(store.packs.count) decks)"
                        : "Bundled content · server unreachable",
                    systemImage: store.source == .server ? "cloud.fill" : "internaldrive"
                )
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("RustChap")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .onAppear {
            // Screenshot automation: `--profile` opens the profile sheet.
            if ProcessInfo.processInfo.arguments.contains("--profile") {
                showProfile = true
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func deckRow(_ deck: ContentStore.LoadedPack, unlocked: Bool) -> some View {
        // Locked decks with content stay browsable — tap to preview the list.
        if !deck.puzzles.isEmpty {
            NavigationLink(value: Route.deck(deck.id)) {
                deckCard(deck, unlocked: unlocked)
            }
        } else {
            deckCard(deck, unlocked: false)
        }
    }

    private func deckCard(_ deck: ContentStore.LoadedPack, unlocked: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(deck.pack.title)
                        .font(.headline)
                        .foregroundStyle(unlocked ? .primary : .secondary)
                    if deck.id == currentDeckId {
                        Text("Continue")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let description = deck.pack.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            trailing(deck, unlocked: unlocked)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func trailing(_ deck: ContentStore.LoadedPack, unlocked: Bool) -> some View {
        if deck.puzzles.isEmpty {
            Text("Soon")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
        } else if !unlocked {
            Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
        } else {
            let solved = solvedCount(deck)
            let stars = optimalCount(deck)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(solved)/\(deck.puzzles.count)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(solved == deck.puzzles.count ? Color.green : .secondary)
                if stars > 0 {
                    Label("\(stars)", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    // MARK: - Progression

    private func record(for puzzleId: String) -> PuzzleProgressRecord? {
        progress.first { $0.puzzleId == puzzleId }
    }

    private func solvedCount(_ deck: ContentStore.LoadedPack) -> Int {
        deck.puzzles.filter { record(for: $0.id)?.solved == true }.count
    }

    private func optimalCount(_ deck: ContentStore.LoadedPack) -> Int {
        deck.puzzles.filter { record(for: $0.id)?.bestRank == .optimal }.count
    }

    private func isUnlocked(_ index: Int) -> Bool {
        Progression.isUnlocked(
            deckIndex: index, packs: store.packs,
            solved: Progression.solvedIds(progress)
        )
    }
}
