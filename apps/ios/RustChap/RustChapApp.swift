import SwiftUI

@main
struct RustChapApp: App {
    @State private var store = ContentStore()
    @State private var path: [String] = []

    init() {
        // Debug/screenshot affordance: `--open <puzzle-id>` deep-links straight
        // to a puzzle (used by simulator automation; harmless in production).
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--open"), args.indices.contains(flag + 1) {
            _path = State(initialValue: [args[flag + 1]])
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                TrackListView()
                    .navigationDestination(for: String.self) { puzzleId in
                        if let loaded = store.puzzle(id: puzzleId) {
                            PuzzleScreen(loaded: loaded, path: $path)
                        }
                    }
            }
            .environment(store)
            .task {
                await store.refreshFromServer()
            }
        }
    }
}
