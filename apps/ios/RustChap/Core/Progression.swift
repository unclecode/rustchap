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

    /// Decks chain WITHIN their level only: the first deck of every level is
    /// always open (levels are free to enter), later decks need the previous
    /// same-level deck complete.
    static func isUnlocked(deckId: String, packs: [ContentStore.LoadedPack], solved: Set<String>) -> Bool {
        guard let deck = packs.first(where: { $0.id == deckId }) else { return false }
        let chain = packs.filter {
            ContentStore.levelId(of: $0.pack) == ContentStore.levelId(of: deck.pack)
        }
        guard let index = chain.firstIndex(where: { $0.id == deckId }) else { return false }
        return index == 0 || isComplete(chain[index - 1], solved: solved)
    }
}
