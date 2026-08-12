// Where the player last was, so a relaunch can offer to pick up there.
//
// Deliberately NOT full state restoration: RustChap opens on the deck list
// because that screen carries the progress picture, and being dropped straight
// back into a puzzle you quit is hostile. One tap gets you back instead.

import Foundation

enum ResumePoint {
    private static let key = "lastPuzzleId"

    static func record(_ puzzleId: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: key) != puzzleId else { return }
        defaults.set(puzzleId, forKey: key)
        // UserDefaults flushes lazily. A force quit from the app switcher (and
        // `devicectl --terminate-existing`) is a SIGKILL, so an unflushed value
        // dies with the process and the resume row never appears. One tiny key
        // written rarely: push it out now.
        defaults.synchronize()
    }

    static var puzzleId: String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
