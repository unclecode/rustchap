// Skills review state: one durable record per card, plus the mastery rules.
//
// Phase 1 deliberately has NO scheduler. Sorting is weakest-first from your
// own ratings; time is not an input yet (that is phase 3). Conventions follow
// the standard SRS model rather than inventing one:
//   - a failed card returns later in the SAME run (Anki's "learning steps")
//   - failure drops one state, it never resets to zero
//   - repeated failures flag the card quietly (Anki's "leech") so it can be
//     rewritten rather than blaming the player

import Foundation
import SwiftData

/// How the player rated a recall attempt.
enum ReviewRating: String, Codable, CaseIterable {
    case got, shaky, missed

    var label: String {
        switch self {
        case .got: "Got it"
        case .shaky: "Shaky"
        case .missed: "No idea"
        }
    }
}

/// Visible confidence in one card. New → Learning → Solid → Mastered.
enum MasteryState: Int, Codable, Comparable, CaseIterable {
    case new = 0, learning, solid, mastered

    var label: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .solid: "Solid"
        case .mastered: "Mastered"
        }
    }

    static func < (lhs: MasteryState, rhs: MasteryState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@Model
final class ReviewRecord {
    @Attribute(.unique) var cardId: String
    /// Raw rating history, newest last, stored as raw values for portability.
    var ratingsRaw: [String]
    /// When each rating happened, parallel to `ratingsRaw`.
    var ratingDates: [Date] = []
    var lastReviewed: Date?
    var stateRaw: Int

    init(cardId: String) {
        self.cardId = cardId
        ratingsRaw = []
        ratingDates = []
        lastReviewed = nil
        stateRaw = MasteryState.new.rawValue
    }

    /// Rating history newest first, with dates, for the detail screen.
    var timeline: [(rating: ReviewRating, date: Date)] {
        zip(ratings, ratingDates).map { ($0, $1) }.reversed()
    }

    var state: MasteryState {
        get { MasteryState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    var ratings: [ReviewRating] {
        ratingsRaw.compactMap(ReviewRating.init(rawValue:))
    }

    var reviewCount: Int { ratingsRaw.count }

    /// Standard leech rule: a card that keeps slipping is the card's fault,
    /// not the player's. Flagged quietly so it can be rewritten.
    var keepsSlipping: Bool {
        ratings.filter { $0 == .missed }.count >= 3
    }

    /// Record one rating and move the mastery state.
    /// Success climbs one step; "shaky" holds; a miss drops one step.
    func apply(_ rating: ReviewRating) {
        ratingsRaw.append(rating.rawValue)
        ratingDates.append(.now)
        lastReviewed = .now
        switch rating {
        case .got:
            state = MasteryState(rawValue: min(state.rawValue + 1, MasteryState.mastered.rawValue)) ?? .solid
        case .shaky:
            if state == .new { state = .learning }
        case .missed:
            state = MasteryState(rawValue: max(state.rawValue - 1, MasteryState.learning.rawValue)) ?? .learning
        }
    }
}

enum ReviewProgress {
    static func records(_ all: [ReviewRecord]) -> [String: ReviewRecord] {
        Dictionary(all.map { ($0.cardId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Fetch or create the record for a card.
    static func record(
        for cardId: String, in context: ModelContext, cache: [String: ReviewRecord]
    ) -> ReviewRecord {
        if let existing = cache[cardId] { return existing }
        let fresh = ReviewRecord(cardId: cardId)
        context.insert(fresh)
        return fresh
    }

    /// Weakest first: lower mastery leads, then fewer reviews, then id for a
    /// stable order. No time input in phase 1 by design.
    static func weakestFirst(
        _ cards: [ReviewCard], records: [String: ReviewRecord]
    ) -> [ReviewCard] {
        cards.sorted { a, b in
            let ra = records[a.id], rb = records[b.id]
            let sa = ra?.state ?? .new, sb = rb?.state ?? .new
            if sa != sb { return sa < sb }
            let ca = ra?.reviewCount ?? 0, cb = rb?.reviewCount ?? 0
            if ca != cb { return ca < cb }
            return a.id < b.id
        }
    }

    /// How many of a concept's cards have reached at least `state`.
    static func count(
        _ cards: [ReviewCard], records: [String: ReviewRecord], atLeast state: MasteryState
    ) -> Int {
        cards.filter { (records[$0.id]?.state ?? .new) >= state }.count
    }

    /// A concept's overall state is its weakest card: you know a topic only
    /// as well as the part you know worst.
    static func conceptState(
        _ cards: [ReviewCard], records: [String: ReviewRecord]
    ) -> MasteryState {
        cards.map { records[$0.id]?.state ?? .new }.min() ?? .new
    }
}
