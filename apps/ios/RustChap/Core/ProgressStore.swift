// Local, durable progress (build-order step 18). SwiftData holds the user
// state; puzzles stay versioned JSON. Merge rules from the plan: solved beats
// unsolved, better rank beats worse, the newest attempt never automatically
// beats the best one.

import Foundation
import SwiftData

@Model
final class PuzzleProgressRecord {
    @Attribute(.unique) var puzzleId: String
    var puzzleVersion: Int
    var solved: Bool
    /// Raw EvalResult.Rank ("solved" / "fluent" / "optimal"), nil until solved.
    var bestRankRaw: String?
    /// Best solution's metrics, JSON-encoded [String: Int].
    var bestMetricsJSON: String
    var attemptCount: Int
    var firstSolvedAt: Date?
    var bestSolvedAt: Date?
    var updatedAt: Date

    init(puzzleId: String, puzzleVersion: Int) {
        self.puzzleId = puzzleId
        self.puzzleVersion = puzzleVersion
        solved = false
        bestRankRaw = nil
        bestMetricsJSON = "{}"
        attemptCount = 0
        firstSolvedAt = nil
        bestSolvedAt = nil
        updatedAt = .now
    }

    var bestRank: EvalResult.Rank? {
        bestRankRaw.flatMap(EvalResult.Rank.init(rawValue:))
    }

    var bestMetrics: [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: Data(bestMetricsJSON.utf8))) ?? [:]
    }
}

enum ProgressRecorder {
    /// Fold one evaluation into the durable record for its puzzle.
    static func record(
        in context: ModelContext,
        puzzle: Puzzle,
        result: EvalResult
    ) {
        let record = fetch(puzzleId: puzzle.id, in: context)
            ?? {
                let fresh = PuzzleProgressRecord(puzzleId: puzzle.id, puzzleVersion: puzzle.version)
                context.insert(fresh)
                return fresh
            }()

        // A republished puzzle invalidates old bests (answers/scores may have
        // changed) but keeps the attempt history.
        if record.puzzleVersion != puzzle.version {
            record.puzzleVersion = puzzle.version
            record.solved = false
            record.bestRankRaw = nil
            record.bestMetricsJSON = "{}"
            record.firstSolvedAt = nil
            record.bestSolvedAt = nil
        }

        record.attemptCount += 1
        record.updatedAt = .now

        if result.status == .solved, let rank = result.rank {
            if !record.solved {
                record.solved = true
                record.firstSolvedAt = .now
            }
            let currentBest = record.bestRank
            if currentBest == nil || rank > currentBest! {
                record.bestRankRaw = rank.rawValue
                record.bestSolvedAt = .now
                if let data = try? JSONEncoder().encode(result.metrics) {
                    record.bestMetricsJSON = String(decoding: data, as: UTF8.self)
                }
            }
        }
        try? context.save()
    }

    static func fetch(puzzleId: String, in context: ModelContext) -> PuzzleProgressRecord? {
        var descriptor = FetchDescriptor<PuzzleProgressRecord>(
            predicate: #Predicate { $0.puzzleId == puzzleId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
