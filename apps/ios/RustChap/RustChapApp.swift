import SwiftUI

@main
struct RustChapApp: App {
    @State private var store = ContentStore()
    @State private var path: [String] = []

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
        }
    }
}
