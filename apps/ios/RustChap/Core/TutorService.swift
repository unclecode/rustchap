// The on-device AI tutor's non-UI half: availability gating and grounding
// assembly. Design rule from the phase-8 spike: the model NEVER answers from
// its own weights alone — every session is pinned to reference material the
// app bundles (concept lectures, puzzle explanations, real diagnostics),
// because ungrounded answers were confidently wrong about Rust.

import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the "Ask the tutor" affordance should exist at all: a configured
/// cloud engine, or the on-device model, can answer. When neither can, the
/// button simply never appears.
enum TutorAvailability {
    static var isAvailable: Bool {
        if TutorSettings.cloudConfigured { return true }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
        #else
        return false
        #endif
    }
}

struct TutorMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable {
        case player
        case tutor
        case failure
    }

    var id = UUID()
    let role: Role
    var text: String
    /// Which engine produced a tutor answer ("DeepSeek V4 Flash", "On-device").
    /// Optional so transcripts saved before this field decode unchanged.
    var source: String?
}

// MARK: - Durable conversation (SwiftData)

/// One persisted tutor conversation per surface: "home", "deck:<id>", or
/// "puzzle:<id>". Reopening the tutor on the same surface resumes its own
/// thread. No history browser — the scoping IS the navigation.
@Model
final class TutorConversationRecord {
    @Attribute(.unique) var subjectId: String
    /// JSON-encoded [TutorMessage] — same idiom as PuzzleProgressRecord's
    /// bestMetricsJSON.
    var messagesJSON: String
    var updatedAt: Date

    init(subjectId: String) {
        self.subjectId = subjectId
        messagesJSON = "[]"
        updatedAt = .now
    }
}

enum TutorConversation {
    /// Stored threads beyond this are pruned, oldest first.
    private static let maxConversations = 30

    static func load(_ subjectId: String, in context: ModelContext) -> [TutorMessage] {
        guard let record = fetch(subjectId, in: context) else { return [] }
        return (try? JSONDecoder().decode(
            [TutorMessage].self, from: Data(record.messagesJSON.utf8))) ?? []
    }

    /// Persist the transcript; transient failure rows are not worth keeping.
    static func save(_ messages: [TutorMessage], subjectId: String, in context: ModelContext) {
        let durable = messages.filter { $0.role != .failure }
        let record = fetch(subjectId, in: context) ?? {
            let fresh = TutorConversationRecord(subjectId: subjectId)
            context.insert(fresh)
            return fresh
        }()
        if let data = try? JSONEncoder().encode(durable) {
            record.messagesJSON = String(decoding: data, as: UTF8.self)
        }
        record.updatedAt = .now
        prune(in: context)
        try? context.save()
    }

    static func clear(_ subjectId: String, in context: ModelContext) {
        if let record = fetch(subjectId, in: context) {
            context.delete(record)
            try? context.save()
        }
    }

    private static func fetch(
        _ subjectId: String, in context: ModelContext
    ) -> TutorConversationRecord? {
        var descriptor = FetchDescriptor<TutorConversationRecord>(
            predicate: #Predicate { $0.subjectId == subjectId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func prune(in context: ModelContext) {
        let descriptor = FetchDescriptor<TutorConversationRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > maxConversations
        else { return }
        for record in all.dropFirst(maxConversations) {
            context.delete(record)
        }
    }
}

/// Everything a tutor session is allowed to know, assembled per screen.
/// Each surface also names its conversation: home, one per deck, one per
/// puzzle — reopening the tutor there resumes that thread.
struct TutorContext {
    /// Conversation key: "home", "deck:<id>", or "puzzle:<id>".
    let subjectId: String
    /// Shown in the sheet header ("Asking about: Copy or Move?").
    let subject: String?
    /// Reference material the session is pinned to.
    let material: String
    /// Contextual starter questions shown as tappable chips.
    let suggested: [String]

    // MARK: - Builders

    /// Home level: the whole concept library, summaries only.
    static func global(concepts: [Concept]) -> TutorContext {
        TutorContext(
            subjectId: "home",
            subject: nil,
            material: "# RustChap skill library (summaries)\n\(conceptIndex(concepts))",
            suggested: [
                "When is cloning actually the right call?",
                "What does borrowing really mean in Rust?",
                "Why does Rust make me think about ownership at all?",
            ]
        )
    }

    /// Deck level: the deck's own arc plus the concept summaries.
    static func deck(_ deck: ContentStore.LoadedPack, concepts: [Concept]) -> TutorContext {
        let arc = deck.puzzles
            .map { "- \($0.puzzle.title): \($0.puzzle.goal)" }
            .joined(separator: "\n")
        return TutorContext(
            subjectId: "deck:\(deck.id)",
            subject: deck.pack.title,
            material: """
            # Deck: \(deck.pack.title)
            \(deck.pack.description ?? "")
            ## Its puzzles, in order
            \(arc)
            # RustChap skill library (summaries)
            \(conceptIndex(concepts))
            """,
            suggested: [
                "What is this deck really teaching?",
                "What should I pay attention to in these puzzles?",
                "Where does this topic matter in real code?",
            ]
        )
    }

    private static func conceptIndex(_ concepts: [Concept]) -> String {
        concepts
            .sorted { $0.title < $1.title }
            .map { "- \($0.title): \($0.summary)" }
            .joined(separator: "\n")
    }

    /// Puzzle level: full lectures for the puzzle's own concepts, the code,
    /// the player's current picks, and — when present — the real verdict.
    static func puzzle(
        _ loaded: ContentStore.LoadedPuzzle,
        concepts: [Concept],
        selections: [String: String] = [:],
        blockOrder: [Block] = [],
        chosenCandidate: String? = nil,
        result: EvalResult? = nil,
        pastBest: EvalResult.Rank? = nil
    ) -> TutorContext {
        let puzzle = loaded.puzzle
        var sections: [String] = ["# Puzzle: \(puzzle.title)\nGoal: \(puzzle.goal)"]

        if let pastBest {
            sections.append(
                "## Player's history\nHas already solved this puzzle (best rank: \(pastBest.rawValue)).")
        }

        if case .lesson(let lessonSections) = puzzle.interaction {
            let text = lessonSections.map { section in
                switch section {
                case .prose(let text): text
                case .code(let code, let caption):
                    "```rust\n\(code)\n```" + (caption.map { "\n(\($0))" } ?? "")
                }
            }.joined(separator: "\n\n")
            sections.append("## Lecture text\n\(text)")
        }

        // The code AS THE PLAYER CURRENTLY SEES IT — composed from their live
        // picks, so "my code" means the same thing to the tutor and the player.
        switch puzzle.interaction {
        case .slotSelection(let slots), .minimalEdit(let slots):
            var composed = puzzle.template ?? ""
            var open: [String] = []
            for slot in slots {
                let marker = "⟦\(slot.id)⟧"
                if let choiceId = selections[slot.id],
                   let choice = slot.choices.first(where: { $0.id == choiceId }) {
                    composed = composed.replacingOccurrences(of: marker, with: choice.text)
                } else {
                    composed = composed.replacingOccurrences(
                        of: marker, with: "⟦\(slot.label ?? slot.id)⟧")
                    open.append(slot.label ?? slot.id)
                }
            }
            sections.append(
                "## The player's code right now\n```rust\n\(composed)\n```"
                    + (open.isEmpty ? "" : "\nSlots still unchosen: \(open.joined(separator: ", ")) (shown as ⟦…⟧)."))
            let options = slots.map { slot -> String in
                let current = selections[slot.id]
                    .flatMap { id in slot.choices.first { $0.id == id }?.text }
                let choices = slot.choices.map { "`\($0.text)`" }.joined(separator: ", ")
                return "- \(slot.label ?? slot.id): options \(choices)"
                    + (current.map { " — currently `\($0)`" } ?? " — not chosen yet")
            }
            sections.append("## Editable slots\n" + options.joined(separator: "\n"))
        case .blockArrangement(let prefix, _, let suffix):
            let body = blockOrder.map(\.text).joined(separator: "\n")
            sections.append(
                "## The player's code right now (their current block order)\n```rust\n\(prefix)\n\(body)\n\(suffix)\n```")
        case .bestSolution(let candidates):
            let listing = candidates.map { candidate in
                let mark = candidate.id == chosenCandidate ? " (player's current pick)" : ""
                return "### Candidate \(candidate.id)\(mark)\n```rust\n\(candidate.code)\n```"
            }.joined(separator: "\n")
            sections.append("## The candidate implementations\n\(listing)")
        case .lesson:
            break
        }
        if let result {
            let diags = result.diagnostics
                .map { "- [\($0.category)\($0.rustCode.map { " \($0)" } ?? "")] \($0.message)" }
                .joined(separator: "\n")
            sections.append(
                "## Verdict on the player's submission\nStatus: \(result.status.rawValue)"
                    + (diags.isEmpty ? "" : "\nDiagnostics:\n\(diags)"))
        }
        sections.append("## Why the intended answer is right\n\(puzzle.explanation)")
        for concept in concepts {
            sections.append(
                "## Skill: \(concept.title)\n" + concept.lecture.joined(separator: "\n"))
        }

        var suggested: [String] = []
        if let result {
            suggested.append(
                result.status == .solved
                    ? "Could my answer be more idiomatic?"
                    : "Why exactly doesn't my answer work?")
        }
        suggested.append("Explain the idea this puzzle trains.")
        suggested.append("Where does this matter in real code?")

        return TutorContext(
            subjectId: "puzzle:\(puzzle.id)",
            subject: puzzle.title,
            material: sections.joined(separator: "\n\n"),
            suggested: suggested
        )
    }

    /// The session leash: grounded, honest, concise.
    var instructions: String {
        """
        You are the tutor inside RustChap, a puzzle game that trains Rust instincts. \
        The player is an experienced programmer who is new to Rust. Be direct and \
        technically precise, in under 150 words unless asked for more. Answer ONLY \
        from the reference material below plus what the player shows you; if the \
        material does not cover something, say you are not sure — never invent Rust \
        rules. Prefer guiding the player's thinking over revealing an answer outright, \
        but do answer plainly when they explicitly ask for the solution.

        # Reference material
        \(material)
        """
    }
}
