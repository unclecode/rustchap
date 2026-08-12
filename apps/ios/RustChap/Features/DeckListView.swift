// The home screen: the curriculum as a list of decks (Euclidea's chests, with
// real names). Locked decks stay visible — you can always see the road ahead.
// Two levels only: decks → puzzles.

import SwiftData
import SwiftUI

struct DeckListView: View {
    @Binding var path: [Route]
    @Environment(ContentStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Query private var progress: [PuzzleProgressRecord]
    @State private var showProfile = false
    @State private var showMarkdownPreview = false
    @AppStorage("selectedLevel") private var selectedLevel = ""
    // Same key ResumePoint writes. Reading it through AppStorage means
    // dismissing the banner updates the view straight away.
    @AppStorage("lastPuzzleId") private var lastPuzzleId = ""

    /// The first unlocked, incomplete, non-empty deck — where the player is.
    private var currentDeckId: String? {
        let solved = Progression.solvedIds(progress)
        return store.packs.first { deck in
            !deck.puzzles.isEmpty
                && Progression.isUnlocked(deckId: deck.id, packs: store.packs, solved: solved)
                && !Progression.isComplete(deck, solved: solved)
        }?.id
    }

    /// The level whose grid is showing: the persisted pick when valid,
    /// otherwise wherever the current deck lives, otherwise the first level.
    private var activeLevelId: String {
        let visible = store.visibleLevels
        if visible.contains(where: { $0.id == selectedLevel }) { return selectedLevel }
        if let current = currentDeckId,
           let deck = store.packs.first(where: { $0.id == current }) {
            return ContentStore.levelId(of: deck.pack)
        }
        return visible.first?.id ?? "core"
    }

    /// Where to send the player back to, based on the last node they opened.
    ///
    /// If they left mid-puzzle, that puzzle. If they SOLVED it and then closed
    /// the app -- which is the normal way to stop -- the next unsolved node in
    /// the same deck, because "where I was" means "the next thing to do", not a
    /// puzzle already finished. Hiding the row on solve made it vanish exactly
    /// when it was most wanted, which is why it looked broken.
    ///
    /// Deliberately does not require the deck to be unlocked: if you were in a
    /// puzzle you should be able to get back to it.
    private var resumePuzzle: ContentStore.LoadedPuzzle? {
        let id = lastPuzzleId
        guard !id.isEmpty,
              let last = store.allPuzzles.first(where: { $0.id == id })
        else { return nil }
        let solved = Progression.solvedIds(progress)
        if !solved.contains(id) { return last }
        guard let deck = store.packs.first(where: { $0.id == last.puzzle.track }),
              let index = deck.puzzles.firstIndex(where: { $0.id == id })
        else { return nil }
        // the next unsolved node after it, then anything unsolved before it
        return deck.puzzles[(index + 1)...].first { !solved.contains($0.id) }
            ?? deck.puzzles.first { !solved.contains($0.id) }
    }

    @ViewBuilder
    private func resumeRow(_ loaded: ContentStore.LoadedPuzzle) -> some View {
        let deckId = loaded.puzzle.track
        let deckTitle = store.packs.first { $0.id == deckId }?.pack.title
        HStack(spacing: 12) {
            Button {
                // Push the deck first so Back goes to the puzzle list rather
                // than all the way home.
                path = [.deck(deckId), .puzzle(loaded.id)]
                lastPuzzleId = ""          // one-time: using it consumes it
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.uturn.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loaded.id == lastPuzzleId
                             ? "Pick up where you left off"
                             : "Carry on from here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(loaded.puzzle.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let deckTitle {
                            Text(deckTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                lastPuzzleId = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.tint.opacity(0.30), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.bottom, 4)
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
            if let resume = resumePuzzle {
                resumeRow(resume)
            }
            if store.visibleLevels.count > 1 {
                levelChips
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.packs(in: activeLevelId)) { deck in
                    deckCell(deck, unlocked: isUnlocked(deck))
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
        .skillsButton()
        .scoreboardButton()
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

    private func isUnlocked(_ deck: ContentStore.LoadedPack) -> Bool {
        Progression.isUnlocked(
            deckId: deck.id, packs: store.packs,
            solved: Progression.solvedIds(progress)
        )
    }

    // MARK: - Level chips

    /// The curriculum tier selector: scrollable capsules, App Store style.
    /// Selected chip fills with the app tint and carries that level's progress.
    private var levelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.visibleLevels) { level in
                    levelChip(level)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 10)
    }

    private func levelChip(_ level: Level) -> some View {
        let selected = level.id == activeLevelId
        let decks = store.packs(in: level.id)
        let total = decks.reduce(0) { $0 + $1.puzzles.count }
        let solved = decks.reduce(0) { $0 + solvedCount($1) }
        let stars = decks.reduce(0) { $0 + optimalCount($1) }
        return Button {
            selectedLevel = level.id
        } label: {
            HStack(spacing: 5) {
                Text(level.title)
                    .font(.subheadline.weight(.semibold))
                if total > 0 && solved > 0 {
                    Text("\(solved)/\(total)")
                        .font(.caption2.monospacedDigit())
                        .opacity(0.75)
                }
                if stars > 0 {
                    Label("\(stars)", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(selected ? .white : .yellow)
                        .opacity(selected ? 0.9 : 1)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                selected ? AnyShapeStyle(Color.accentColor)
                         : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: Capsule())
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
