// Skills: everything you have learned, always open, grouped by topic.
//
// Phase 1 of the review feature. No scheduler, no due dates, no counters -
// rows are ordered weakest-first from your own ratings, and the screen is
// only ever a place you choose to visit.

import SwiftData
import SwiftUI

struct SkillsView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var progress: [PuzzleProgressRecord]
    @Query private var reviewRecords: [ReviewRecord]
    @State private var session: ReviewQueue?
    @State private var path: [String] = []

    /// Concepts the player has actually met: taught by a puzzle or lecture
    /// they finished, and carrying at least one review card.
    private var unlockedConcepts: Set<String> {
        let solved = Progression.solvedIds(progress)
        var met: Set<String> = []
        for loaded in store.allPuzzles where solved.contains(loaded.id) {
            met.formUnion(loaded.puzzle.concepts)
        }
        return met.filter { store.reviewCards[$0]?.isEmpty == false }
    }

    private var records: [String: ReviewRecord] {
        ReviewProgress.records(reviewRecords)
    }

    /// Concept id → (when you first met it, and where: deck > puzzle).
    /// Derived from `firstSolvedAt` on progress records, so it needs no new
    /// storage.
    private var unlockInfo: [String: (date: Date, deck: String, puzzle: String)] {
        var out: [String: (date: Date, deck: String, puzzle: String)] = [:]
        for record in progress where record.solved {
            guard let when = record.firstSolvedAt,
                  let loaded = store.puzzle(id: record.puzzleId)
            else { continue }
            let deck = store.pack(containing: record.puzzleId)?.pack.title ?? ""
            for concept in loaded.puzzle.concepts {
                if let existing = out[concept], existing.date <= when { continue }
                out[concept] = (when, deck, loaded.puzzle.title)
            }
        }
        return out
    }

    /// Met within the last week, newest first, at most five - the bridge
    /// between what you just played and what is waiting to be reviewed.
    /// Hidden while everything is recent, since it would just repeat the list.
    private var recentlyLearned: [String] {
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        let info = unlockInfo
        let unlocked = unlockedConcepts
        let recent = unlocked
            .filter { (info[$0]?.date ?? .distantPast) > cutoff }
            .sorted { (info[$0]?.date ?? .distantPast) > (info[$1]?.date ?? .distantPast) }
        return Array(recent.prefix(5))
    }

    /// [(topic title, concept ids)] in curriculum order, minus anything
    /// currently shown under "Recently learned" so no row appears twice.
    private var topics: [(String, [String])] {
        let unlocked = unlockedConcepts.subtracting(recentlyLearned)
        var grouped: [String: [String]] = [:]
        for concept in unlocked.sorted() {
            let topic = store.concepts[concept]?.topic ?? "Other"
            grouped[topic, default: []].append(concept)
        }
        // Teaching order for sections, weakest concept first inside each.
        let topicOrder = store.conceptTopicOrder
        let order = grouped.keys.sorted { a, b in
            (topicOrder.firstIndex(of: a) ?? .max) < (topicOrder.firstIndex(of: b) ?? .max)
        }
        let cache = records
        return order.map { topic in
            let concepts = (grouped[topic] ?? []).sorted { a, b in
                let sa = ReviewProgress.conceptState(store.reviewCards[a] ?? [], records: cache)
                let sb = ReviewProgress.conceptState(store.reviewCards[b] ?? [], records: cache)
                if sa != sb { return sa < sb }
                return (store.concepts[a]?.title ?? a) < (store.concepts[b]?.title ?? b)
            }
            return (topic, concepts)
        }
    }

    private var allUnlockedCards: [ReviewCard] {
        unlockedConcepts.flatMap { store.reviewCards[$0] ?? [] }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if unlockedConcepts.isEmpty {
                    ContentUnavailableView(
                        "Nothing to review yet",
                        systemImage: "brain",
                        description: Text(
                            "Skills appear here as you finish puzzles and lectures. Solve one and come back.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { conceptId in
                ConceptDetailView(
                    concept: store.concepts[conceptId] ?? Concept(
                        id: conceptId, title: conceptId, topic: nil,
                        summary: "", lecture: [], example: nil),
                    cards: store.reviewCards[conceptId] ?? [])
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !allUnlockedCards.isEmpty {
                        Button {
                            session = ReviewQueue(
                                title: "Shuffle",
                                cards: allUnlockedCards.shuffled())
                        } label: {
                            Label("Shuffle all", systemImage: "shuffle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
            .sheet(item: $session) { queue in
                ReviewSessionView(queue: queue)
            }
            .onAppear {
                // Screenshot automation: `--review <conceptId>` jumps straight
                // into that concept's run.
                let args = ProcessInfo.processInfo.arguments
                // Screenshot automation: fabricate a lived-in review history so
                // badges, dots, and the history panel can be verified.
                if args.contains("--seed-reviews") {
                    seedReviews()
                }
                if let flag = args.firstIndex(of: "--concept"),
                   args.indices.contains(flag + 1) {
                    path = [args[flag + 1]]
                }
                if let flag = args.firstIndex(of: "--review"),
                   args.indices.contains(flag + 1) {
                    let conceptId = args[flag + 1]
                    let cards = store.reviewCards[conceptId] ?? []
                    if !cards.isEmpty {
                        session = ReviewQueue(
                            title: store.concepts[conceptId]?.title ?? conceptId,
                            cards: cards)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var list: some View {
        List {
            let recent = recentlyLearned
            if !recent.isEmpty {
                Section("Recently learned") {
                    ForEach(recent, id: \.self) { conceptId in
                        conceptRow(conceptId, showFreshness: true)
                    }
                }
            }
            ForEach(topics, id: \.0) { topic, concepts in
                Section(topic) {
                    ForEach(concepts, id: \.self) { conceptId in
                        conceptRow(conceptId)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func conceptRow(_ conceptId: String, showFreshness: Bool = false) -> some View {
        let cards = store.reviewCards[conceptId] ?? []
        let cache = records
        let state = ReviewProgress.conceptState(cards, records: cache)
        let reviewed = cards.compactMap { cache[$0.id] }
        let solid = ReviewProgress.count(cards, records: cache, atLeast: .solid)
        let slipping = reviewed.contains(where: \.keepsSlipping)
        let concept = store.concepts[conceptId]
        let info = unlockInfo[conceptId]
        return NavigationLink(value: conceptId) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(concept?.title ?? conceptId)
                        .font(.subheadline.weight(.medium))
                    if showFreshness, let info {
                        Text(freshness(info.date))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 4)
                    MasteryBadge(state: state)
                }
                if let summary = concept?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 5) {
                    Text(breakdown(cards.count, solid: solid))
                    if showFreshness, let info {
                        Text("· \(info.deck) › \(info.puzzle)")
                            .lineLimit(1)
                    }
                    ratingDots(reviewed)
                    if slipping {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    /// "3 cards" or "3 cards · 2 solid" once there is progress worth showing.
    private func breakdown(_ total: Int, solid: Int) -> String {
        let base = "\(total) card\(total == 1 ? "" : "s")"
        return solid > 0 ? "\(base) · \(solid) solid" : base
    }

    /// Debug only: plant a plausible rating history across a few cards.
    private func seedReviews() {
        let cache = records
        guard cache.isEmpty else { return }
        let plan: [(String, [ReviewRating])] = [
            ("move.rule.one-owner", [.got, .got, .got]),
            ("move.gotcha.not-a-reference", [.got, .got]),
            ("move.error.e0382", [.got, .shaky]),
            ("borrow.rule.aliasing", [.got, .got, .got, .got]),
            ("borrow.rule.ownership-stays", [.got, .got, .got]),
            ("copy.rule.which-types", [.shaky]),
            ("deref-coercion.rule.why", [.got]),
        ]
        var day = -9.0
        for (cardId, ratings) in plan {
            let entry = ReviewProgress.record(for: cardId, in: modelContext, cache: [:])
            for rating in ratings {
                entry.apply(rating)
                entry.ratingDates[entry.ratingDates.count - 1] =
                    Date.now.addingTimeInterval(day * 24 * 60 * 60)
                day += 1.5
            }
            entry.lastReviewed = entry.ratingDates.last
        }
        try? modelContext.save()
    }

    private func freshness(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        switch days {
        case 0: return "TODAY"
        case 1: return "1D AGO"
        default: return "\(days)D AGO"
        }
    }

    /// The last few ratings, newest last - the history at a glance.
    private func ratingDots(_ records: [ReviewRecord]) -> some View {
        let recent = records
            .sorted { ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast) }
            .flatMap(\.ratings)
            .suffix(5)
        return HStack(spacing: 2) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, rating in
                Circle()
                    .fill(color(for: rating))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func color(for rating: ReviewRating) -> Color {
        switch rating {
        case .got: .green
        case .shaky: .orange
        case .missed: .red
        }
    }

}

/// Entry point: the brain glyph, next to the tutor and the scoreboard.
struct SkillsButton: ViewModifier {
    @State private var showSkills = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSkills = true
                    } label: {
                        Image(systemName: "brain")
                    }
                    .accessibilityLabel("Skills")
                }
            }
            .sheet(isPresented: $showSkills) {
                SkillsView()
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--skills") {
                    showSkills = true
                }
            }
    }
}

extension View {
    func skillsButton() -> some View {
        modifier(SkillsButton())
    }
}
