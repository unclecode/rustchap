// Content + evaluation source of truth for the app. Starts from the bundled
// packs (always available), then refreshes from the server when reachable —
// so new content arrives without an app rebuild, and the app still works in
// airplane mode. Evaluation prefers the server, falling back to the bundled
// outcomes lookup offline.

import Foundation
import Observation

enum ContentSource {
    case bundled
    case server
}

enum EvaluatedVia {
    case serverCached
    case serverCompiled
    case onDevice
}

@MainActor
@Observable
final class ContentStore {
    struct LoadedPuzzle: Identifiable {
        let puzzle: Puzzle
        /// Bundled sidecar for offline evaluation; server-fetched puzzles get
        /// one only when the bundled copy matches id + version.
        let outcomes: Outcomes?
        var id: String { puzzle.id }
    }

    struct LoadedPack: Identifiable {
        let pack: Pack
        let puzzles: [LoadedPuzzle]
        var id: String { pack.id }
    }

    private(set) var packs: [LoadedPack] = []
    /// Curriculum tiers from packs/levels.json, in display order. Always
    /// bundled (the server never overrides structure). Falls back to a single
    /// implicit "core" level when the manifest is missing.
    private(set) var levels: [Level] = []
    private(set) var concepts: [String: Concept] = [:]
    /// Skills section order, from content/concepts/topics.json.
    private(set) var conceptTopicOrder: [String] = []
    /// Recall cards for the Skills surface, grouped by their owning concept.
    private(set) var reviewCards: [String: [ReviewCard]] = [:]
    private(set) var source: ContentSource = .bundled
    private(set) var loadError: String?

    private let api = APIClient.fromEnvironment()
    private var bundledOutcomes: [String: Outcomes] = [:]

    /// Curriculum order comes from packs/index.json in the bundle — the same
    /// source of truth the server reads. Never hardcode the deck list.
    private struct PackIndex: Decodable {
        let order: [String]
    }

    /// The level a deck belongs to; unlabeled packs count as "core".
    nonisolated static func levelId(of pack: Pack) -> String {
        pack.level ?? "core"
    }

    /// Decks of one level, in curriculum order.
    func packs(in levelId: String) -> [LoadedPack] {
        packs.filter { Self.levelId(of: $0.pack) == levelId }
    }

    /// Levels that have any deck at all, built or planned. Planned decks show
    /// as "Soon", so the whole curriculum shape is visible from day one.
    var visibleLevels: [Level] {
        levels.filter { level in !packs(in: level.id).isEmpty }
    }

    init() {
        do {
            packs = try Self.loadBundled()
            levels = Self.loadLevels()
            bundledOutcomes = Dictionary(
                uniqueKeysWithValues: packs.flatMap(\.puzzles).compactMap { loaded in
                    loaded.outcomes.map { (loaded.id, $0) }
                }
            )
            concepts = try Self.loadConcepts()
            conceptTopicOrder = Self.loadConceptTopicOrder()
            reviewCards = Self.loadReviewCards()
        } catch {
            loadError = String(describing: error)
        }
    }

    // MARK: - Server refresh (step 15)

    /// Replace bundled content with the server's copy when reachable.
    /// Silent no-op when the server is down — bundled content keeps working.
    func refreshFromServer() async {
        do {
            let serverPacks = try await api.packs()
            var refreshed: [LoadedPack] = []
            for pack in serverPacks {
                let detail = try await api.packDetail(pack.id)
                let puzzles = detail.puzzles.map { puzzle in
                    let bundled = bundledOutcomes[puzzle.id]
                    let outcomes = (bundled?.puzzleVersion == puzzle.version) ? bundled : nil
                    return LoadedPuzzle(puzzle: puzzle, outcomes: outcomes)
                }
                refreshed.append(LoadedPack(pack: detail.pack, puzzles: puzzles))
            }
            packs = refreshed
            source = .server
        } catch {
            // Server unreachable — stay on bundled content.
        }
    }

    // MARK: - Evaluation (server first, on-device fallback)

    func evaluate(_ loaded: LoadedPuzzle, operations: [PuzzleOperation]) async -> (EvalResult, EvaluatedVia) {
        let body = SubmissionBody(
            puzzleId: loaded.puzzle.id,
            puzzleVersion: loaded.puzzle.version,
            operations: operations
        )
        do {
            let response = try await api.evaluate(puzzleId: loaded.puzzle.id, submission: body)
            return (response.result, response.cached ? .serverCached : .serverCompiled)
        } catch {
            if let outcomes = loaded.outcomes,
               let result = LocalEvaluator(outcomes: outcomes).evaluate(operations) {
                return (result, .onDevice)
            }
            return (
                EvalResult(
                    status: .invalid, rank: nil, metrics: [:],
                    diagnostics: [Diagnostic(
                        category: "offline",
                        message: "The server is unreachable and no on-device answers exist for this puzzle.",
                        slotIds: [], rustCode: nil
                    )]
                ),
                .onDevice
            )
        }
    }

    // MARK: - Lookup

    var allPuzzles: [LoadedPuzzle] { packs.flatMap(\.puzzles) }

    func puzzle(id: String) -> LoadedPuzzle? {
        allPuzzles.first { $0.id == id }
    }

    func pack(containing puzzleId: String) -> LoadedPack? {
        packs.first { pack in pack.puzzles.contains { $0.id == puzzleId } }
    }

    /// Next puzzle within the same deck; nil at the deck's end (the deck-complete
    /// moment belongs to the deck list, where the next chest unlocks).
    func nextPuzzleId(after id: String) -> String? {
        guard let deck = pack(containing: id),
              let index = deck.puzzles.firstIndex(where: { $0.id == id })
        else { return nil }
        return deck.puzzles.indices.contains(index + 1) ? deck.puzzles[index + 1].id : nil
    }

    /// The puzzle's skills, in the order the puzzle declares them.
    func concepts(for puzzle: Puzzle) -> [Concept] {
        puzzle.concepts.compactMap { concepts[$0] }
    }

    // MARK: - Bundled content

    private static func loadConcepts() throws -> [String: Concept] {
        guard let root = Bundle.main.url(forResource: "concepts", withExtension: nil) else {
            return [:]
        }
        let decoder = JSONDecoder()
        var result: [String: Concept] = [:]
        let files = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            // topics.json sits beside the concepts and is not one; skip
            // anything that is not a concept rather than failing the load.
            guard file.lastPathComponent != "topics.json",
                  let concept = try? decoder.decode(Concept.self, from: Data(contentsOf: file))
            else { continue }
            result[concept.id] = concept
        }
        return result
    }

    private struct TopicOrder: Decodable {
        let topics: [String]
    }

    private static func loadConceptTopicOrder() -> [String] {
        guard let root = Bundle.main.url(forResource: "concepts", withExtension: nil),
              let data = try? Data(contentsOf: root.appendingPathComponent("topics.json")),
              let order = try? JSONDecoder().decode(TopicOrder.self, from: data)
        else { return [] }
        return order.topics
    }

    /// Cards keyed by their first concept; sorted by kind for a stable run order.
    private static func loadReviewCards() -> [String: [ReviewCard]] {
        guard let root = Bundle.main.url(forResource: "review", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: root, includingPropertiesForKeys: nil)
        else { return [:] }
        let decoder = JSONDecoder()
        var out: [String: [ReviewCard]] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let card = try? decoder.decode(ReviewCard.self, from: data)
            else { continue }
            out[card.conceptId, default: []].append(card)
        }
        for key in out.keys {
            out[key]?.sort { $0.id < $1.id }
        }
        return out
    }

    private struct LevelManifest: Decodable {
        let levels: [Level]
    }

    private static func loadLevels() -> [Level] {
        guard let root = Bundle.main.url(forResource: "packs", withExtension: nil),
              let data = try? Data(contentsOf: root.appendingPathComponent("levels.json")),
              let manifest = try? JSONDecoder().decode(LevelManifest.self, from: data)
        else {
            return [Level(id: "core", title: "Core", tagline: nil)]
        }
        return manifest.levels
    }

    private static func loadBundled() throws -> [LoadedPack] {
        guard let root = Bundle.main.url(forResource: "packs", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        let index = try decoder.decode(
            PackIndex.self,
            from: Data(contentsOf: root.appendingPathComponent("index.json"))
        )
        var loaded: [LoadedPack] = []
        for track in index.order {
            let packDir = root.appendingPathComponent(track)
            guard let packData = try? Data(contentsOf: packDir.appendingPathComponent("pack.json"))
            else { continue }
            let pack = try decoder.decode(Pack.self, from: packData)
            var puzzles: [LoadedPuzzle] = []
            for puzzleId in pack.order {
                let puzzle = try decoder.decode(
                    Puzzle.self,
                    from: Data(contentsOf: packDir.appendingPathComponent("puzzles/\(puzzleId).json"))
                )
                let outcomes = try? decoder.decode(
                    Outcomes.self,
                    from: Data(contentsOf: packDir.appendingPathComponent("outcomes/\(puzzleId).json"))
                )
                puzzles.append(LoadedPuzzle(puzzle: puzzle, outcomes: outcomes))
            }
            loaded.append(LoadedPack(pack: pack, puzzles: puzzles))
        }
        return loaded
    }
}
