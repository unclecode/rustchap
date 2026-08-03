import SwiftUI

struct TrackListView: View {
    @Environment(ContentStore.self) private var store

    var body: some View {
        List {
            if let error = store.loadError {
                Text("Content failed to load: \(error)")
                    .foregroundStyle(.red)
            }
            ForEach(store.packs) { loadedPack in
                Section(loadedPack.pack.title) {
                    ForEach(loadedPack.puzzles) { loaded in
                        NavigationLink(value: loaded.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loaded.puzzle.title)
                                    .font(.headline)
                                Text(loaded.puzzle.goal)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("RustChap")
    }
}
