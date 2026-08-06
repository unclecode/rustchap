// One topic, everything in one place: what it is, how well you know it,
// the two things you can do with it (review or re-read), your rating history,
// each card's own state, and which puzzles taught it.
//
// This screen is the answer to "what do I actually know?" - the Skills list
// shows the shape, this shows the substance.

import SwiftData
import SwiftUI

struct ConceptDetailView: View {
    let concept: Concept
    let cards: [ReviewCard]

    @Environment(ContentStore.self) private var store
    @Query private var progress: [PuzzleProgressRecord]
    @Query private var reviewRecords: [ReviewRecord]
    @State private var session: ReviewQueue?
    @State private var showLecture = false

    private var records: [String: ReviewRecord] { ReviewProgress.records(reviewRecords) }

    /// Puzzles and lectures that teach this concept, in curriculum order,
    /// with what you scored on each.
    private var taughtBy: [(title: String, detail: String, tint: Color)] {
        let solved = Progression.solvedIds(progress)
        return store.allPuzzles
            .filter { $0.puzzle.concepts.contains(concept.id) && solved.contains($0.id) }
            .map { loaded in
                let record = progress.first { $0.puzzleId == loaded.id }
                if loaded.puzzle.interaction.isLesson {
                    return (loaded.puzzle.title, "lecture", Color.secondary)
                }
                let rank = record?.bestRank
                return (
                    loaded.puzzle.title,
                    rank.map { $0 == .optimal ? "★ Optimal" : $0.rawValue.capitalized } ?? "solved",
                    rank == .optimal ? Color.yellow : Color.green
                )
            }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(concept.title)
                        .font(.title3.weight(.bold))
                    Text(concept.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        MasteryBadge(state: ReviewProgress.conceptState(cards, records: records))
                        Text(cardBreakdown)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }

            // The two things you can do, given the weight they deserve.
            Section {
                HStack(spacing: 10) {
                    Button {
                        session = ReviewQueue(
                            title: concept.title,
                            cards: ReviewProgress.weakestFirst(cards, records: records))
                    } label: {
                        Text("Review \(cards.count) card\(cards.count == 1 ? "" : "s")")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cards.isEmpty)

                    Button {
                        showLecture = true
                    } label: {
                        Text("Read the lecture")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !timeline.isEmpty {
                Section("Review history") {
                    ForEach(Array(timeline.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(relative(entry.date))
                                .font(.subheadline)
                            Spacer()
                            Text(entry.rating.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(tint(entry.rating))
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                }
            }

            Section("The cards") {
                ForEach(cards) { card in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title)
                                .font(.subheadline)
                            Text(card.kind.label.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        Spacer(minLength: 6)
                        MasteryBadge(state: records[card.id]?.state ?? .new)
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                }
            }

            if !taughtBy.isEmpty {
                Section("Where you learned it") {
                    ForEach(Array(taughtBy.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.title)
                                .font(.subheadline)
                            Spacer()
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(item.tint)
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                }
            }
        }
        .navigationTitle(concept.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $session) { queue in
            ReviewSessionView(queue: queue)
        }
        .sheet(isPresented: $showLecture) {
            NavigationStack {
                ConceptLectureView(concept: concept)
                    .navigationTitle(concept.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
                    }
            }
        }
    }

    private var cardBreakdown: String {
        let solid = ReviewProgress.count(cards, records: records, atLeast: .solid)
        let base = "\(cards.count) card\(cards.count == 1 ? "" : "s")"
        return solid > 0 ? "\(base) · \(solid) solid" : base
    }

    /// Every rating across the concept's cards, newest first.
    private var timeline: [(rating: ReviewRating, date: Date)] {
        cards.compactMap { records[$0.id] }
            .flatMap(\.timeline)
            .sorted { $0.date > $1.date }
    }

    private func tint(_ rating: ReviewRating) -> Color {
        switch rating {
        case .got: .green
        case .shaky: .orange
        case .missed: .red
        }
    }

    private func relative(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}

/// Shared mastery pill, used by the list and the detail screen.
struct MasteryBadge: View {
    let state: MasteryState

    var body: some View {
        let tint: Color = switch state {
        case .new: .secondary
        case .learning: .orange
        case .solid: .green
        case .mastered: .yellow
        }
        return Text(state.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
