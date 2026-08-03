// Loads the bundled puzzle packs (content/packs, shipped as a folder
// reference) and exposes them in curriculum order.

import Foundation
import Observation

@MainActor
@Observable
final class ContentStore {
    struct LoadedPuzzle: Identifiable {
        let puzzle: Puzzle
        let outcomes: Outcomes
        var id: String { puzzle.id }
    }

    struct LoadedPack: Identifiable {
        let pack: Pack
        let puzzles: [LoadedPuzzle]
        var id: String { pack.id }
    }

    private(set) var packs: [LoadedPack] = []
    private(set) var concepts: [String: Concept] = [:]
    private(set) var loadError: String?

    private static let trackOrder = [
        "move-or-borrow",
        "remove-the-clone",
        "repair-the-lifetime",
        "build-the-iterator",
        "design-the-api",
    ]

    init() {
        do {
            packs = try Self.load()
            concepts = try Self.loadConcepts()
        } catch {
            loadError = String(describing: error)
        }
    }

    /// The puzzle's skills, in the order the puzzle declares them.
    func concepts(for puzzle: Puzzle) -> [Concept] {
        puzzle.concepts.compactMap { concepts[$0] }
    }

    var allPuzzles: [LoadedPuzzle] { packs.flatMap(\.puzzles) }

    func puzzle(id: String) -> LoadedPuzzle? {
        allPuzzles.first { $0.id == id }
    }

    func nextPuzzleId(after id: String) -> String? {
        let all = allPuzzles
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        return all.indices.contains(index + 1) ? all[index + 1].id : nil
    }

    private static func loadConcepts() throws -> [String: Concept] {
        guard let root = Bundle.main.url(forResource: "concepts", withExtension: nil) else {
            return [:]
        }
        let decoder = JSONDecoder()
        var result: [String: Concept] = [:]
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            let concept = try decoder.decode(Concept.self, from: Data(contentsOf: file))
            result[concept.id] = concept
        }
        return result
    }

    private static func load() throws -> [LoadedPack] {
        guard let root = Bundle.main.url(forResource: "packs", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        var loaded: [LoadedPack] = []
        for track in trackOrder {
            let packDir = root.appendingPathComponent(track)
            let pack = try decoder.decode(
                Pack.self,
                from: Data(contentsOf: packDir.appendingPathComponent("pack.json"))
            )
            var puzzles: [LoadedPuzzle] = []
            for puzzleId in pack.order {
                let puzzle = try decoder.decode(
                    Puzzle.self,
                    from: Data(contentsOf: packDir.appendingPathComponent("puzzles/\(puzzleId).json"))
                )
                let outcomes = try decoder.decode(
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
