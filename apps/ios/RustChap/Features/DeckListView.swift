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
    @State private var showMarkdownPreview = false

    /// The first unlocked, incomplete, non-empty deck — where the player is.
    private var currentDeckId: String? {
        let solved = Progression.solvedIds(progress)
        return store.packs.enumerated().first { index, deck in
            !deck.puzzles.isEmpty
                && Progression.isUnlocked(deckIndex: index, packs: store.packs, solved: solved)
                && !Progression.isComplete(deck, solved: solved)
        }?.element.id
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            if let error = store.loadError {
                Text("Content failed to load: \(error)")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(store.packs.enumerated()), id: \.element.id) { index, deck in
                    deckCell(deck, unlocked: isUnlocked(index))
                }
            }
            .padding(.horizontal)

            Label(
                store.source == .server
                    ? "Content from server (\(store.packs.count) decks)"
                    : "Bundled content · server unreachable",
                systemImage: store.source == .server ? "cloud.fill" : "internaldrive"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 14)
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
        .tutorButton { .global(concepts: Array(store.concepts.values)) }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showMarkdownPreview) {
            TutorMarkdownPreviewSheet()
        }
        .onAppear {
            // Screenshot automation: `--profile` opens the profile sheet;
            // `--md-preview` shows the tutor markdown renderer (works without
            // Foundation Models, so the simulator can verify it).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--profile") {
                showProfile = true
            }
            if args.contains("--md-preview") {
                showMarkdownPreview = true
            }
        }
    }

    // MARK: - Grid cells

    @ViewBuilder
    private func deckCell(_ deck: ContentStore.LoadedPack, unlocked: Bool) -> some View {
        // Locked decks with content stay browsable — tap to preview the list.
        if !deck.puzzles.isEmpty {
            NavigationLink(value: Route.deck(deck.id)) {
                deckCard(deck, unlocked: unlocked)
            }
            .buttonStyle(.plain)
        } else {
            deckCard(deck, unlocked: false)
        }
    }

    private func deckCard(_ deck: ContentStore.LoadedPack, unlocked: Bool) -> some View {
        let accent = Self.accentColor(deck.pack.accent)
        let isCurrent = deck.id == currentDeckId
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: deck.pack.icon ?? "square.stack.3d.up.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(accent.gradient, in: RoundedRectangle(cornerRadius: 10))
                if let currency = deckCurrency(deck) {
                    // The deck's cost currency — the letter its puzzles play for.
                    Text(currency)
                        .font(.caption.monospaced().bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(accent)
                }
                Spacer()
                statusBadge(deck, unlocked: unlocked)
            }
            Text(deck.pack.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(unlocked ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 36, alignment: .topLeading)
            if isCurrent {
                Text("Continue")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(accent)
            } else {
                progressLine(deck, unlocked: unlocked)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isCurrent ? accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .opacity(unlocked ? 1 : (deck.puzzles.isEmpty ? 0.55 : 0.65))
    }

    @ViewBuilder
    private func statusBadge(_ deck: ContentStore.LoadedPack, unlocked: Bool) -> some View {
        if deck.puzzles.isEmpty {
            Text("Soon")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if !unlocked {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else if solvedCount(deck) == deck.puzzles.count {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func progressLine(_ deck: ContentStore.LoadedPack, unlocked: Bool) -> some View {
        if deck.puzzles.isEmpty {
            Text("In preparation")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if !unlocked {
            Text("Locked")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            let solved = solvedCount(deck)
            let stars = optimalCount(deck)
            HStack(spacing: 8) {
                Text("\(solved)/\(deck.puzzles.count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(solved == deck.puzzles.count ? Color.green : .secondary)
                if stars > 0 {
                    Label("\(stars)", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    /// The deck's dominant primary metric, as its cost letter ("C", "M", …).
    private func deckCurrency(_ deck: ContentStore.LoadedPack) -> String? {
        let primaries = deck.puzzles.compactMap { $0.puzzle.scoring?.primary }
        guard !primaries.isEmpty else { return nil }
        var frequency: [String: Int] = [:]
        for primary in primaries { frequency[primary, default: 0] += 1 }
        guard let top = frequency.max(by: { $0.value < $1.value }) else { return nil }
        return CostLanguage.letter(top.key)
    }

    /// Named accent → platform color; unknown names fall back to the app tint.
    static func accentColor(_ name: String?) -> Color {
        switch name {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        default: .accentColor
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
