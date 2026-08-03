// Deck lock/complete rules, shared by the deck list and deck detail.
// Locked decks are browsable (you can see what's ahead) but not playable.

import Foundation

enum Progression {
    static func solvedIds(_ records: [PuzzleProgressRecord]) -> Set<String> {
        Set(records.filter(\.solved).map(\.puzzleId))
    }

    /// Complete = has content AND every puzzle solved. An empty (planned)
    /// deck never completes, so nothing after it unlocks.
    static func isComplete(_ deck: ContentStore.LoadedPack, solved: Set<String>) -> Bool {
        !deck.puzzles.isEmpty && deck.puzzles.allSatisfy { solved.contains($0.id) }
    }

    static func isUnlocked(deckIndex: Int, packs: [ContentStore.LoadedPack], solved: Set<String>) -> Bool {
        deckIndex == 0 || isComplete(packs[deckIndex - 1], solved: solved)
    }

    static func isUnlocked(deckId: String, packs: [ContentStore.LoadedPack], solved: Set<String>) -> Bool {
        guard let index = packs.firstIndex(where: { $0.id == deckId }) else { return false }
        return isUnlocked(deckIndex: index, packs: packs, solved: solved)
    }
}
