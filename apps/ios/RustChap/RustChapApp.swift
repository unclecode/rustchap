import SwiftData
import SwiftUI

/// Two-level navigation: decks → puzzles. Nothing deeper, by design.
enum Route: Hashable {
    case deck(String)
    case puzzle(String)
}

@main
struct RustChapApp: App {
    @State private var store = ContentStore()
    @State private var sync: SyncService
    @State private var path: [Route] = []
    @AppStorage("appearance") private var appearance = "system"
    private let container: ModelContainer

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    init() {
        let container = try! ModelContainer(
            for: PuzzleProgressRecord.self, TutorConversationRecord.self)
        self.container = container
        _sync = State(initialValue: SyncService(container: container))

        // Debug/screenshot affordance: `--open <puzzle-or-deck-id>` deep-links
        // (used by simulator automation; harmless in production).
        TutorProbe.runIfRequested()
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--open"), args.indices.contains(flag + 1) {
            let id = args[flag + 1]
            if id.contains(".") {
                let deckId = id.split(separator: ".").dropLast().joined(separator: ".")
                _path = State(initialValue: [.deck(deckId), .puzzle(id)])
            } else {
                _path = State(initialValue: [.deck(id)])
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                DeckListView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .deck(let deckId):
                            if let deck = store.packs.first(where: { $0.id == deckId }) {
                                DeckDetailView(deck: deck)
                            }
                        case .puzzle(let puzzleId):
                            if let loaded = store.puzzle(id: puzzleId) {
                                // Per-puzzle identity: replacing the path (Next puzzle)
                                // must not reuse the previous screen's @State.
                                PuzzleScreen(loaded: loaded, path: $path)
                                    .id(puzzleId)
                            }
                        }
                    }
            }
            .environment(store)
            .environment(sync)
            .preferredColorScheme(colorScheme)
            .task {
                await store.refreshFromServer()
                await sync.bootstrap()
            }
        }
        .modelContainer(container)
    }
}
