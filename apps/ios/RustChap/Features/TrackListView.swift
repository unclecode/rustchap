import SwiftData
import SwiftUI

struct TrackListView: View {
    @Environment(ContentStore.self) private var store
    @Query private var progress: [PuzzleProgressRecord]

    private func record(for puzzleId: String) -> PuzzleProgressRecord? {
        progress.first { $0.puzzleId == puzzleId }
    }

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
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(loaded.puzzle.title)
                                        .font(.headline)
                                    Text(loaded.puzzle.goal)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                progressBadge(for: loaded.id)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            Section {
            } footer: {
                Label(
                    store.source == .server
                        ? "Content from server (\(store.packs.count) packs)"
                        : "Bundled content · server unreachable",
                    systemImage: store.source == .server ? "cloud.fill" : "internaldrive"
                )
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("RustChap")
    }

    @ViewBuilder
    private func progressBadge(for puzzleId: String) -> some View {
        if let record = record(for: puzzleId), record.solved {
            switch record.bestRank {
            case .optimal:
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(.yellow)
            case .fluent:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.teal)
            default:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else if let record = record(for: puzzleId), record.attemptCount > 0 {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.orange)
        }
    }
}
