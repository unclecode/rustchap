// One tap from the goal chip or the live meter: what the cost letters mean.
// This puzzle's letters on top, the other decks' currencies dimmed below.
// Deliberately a half-height sheet (approved exception to the all-large rule):
// it is a glance card, not a document.

import SwiftUI

struct CostLegendSheet: View {
    /// Metric keys the current puzzle scores — shown first, tagged, bright.
    let activeKeys: Set<String>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows, id: \.key) { metric in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(metric.letter)
                                .font(.body.monospaced().bold())
                                .foregroundStyle(metric.legendColor)
                                .frame(width: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(metric.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if activeKeys.contains(metric.key) {
                                Text("this puzzle")
                                    .font(.caption2)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(.yellow.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .opacity(activeKeys.contains(metric.key) ? 1 : 0.45)
                        .listRowSeparator(.hidden)
                    }
                } footer: {
                    Text("The ★ goal is this puzzle's best-known budget. Match it to earn the star. The compiler has the final word when you Run.")
                }
            }
            .listStyle(.plain)
            .navigationTitle("Cost letters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Active letters first, keeping the canonical order within each group.
    private var rows: [CostMetric] {
        CostLanguage.all.filter { activeKeys.contains($0.key) }
            + CostLanguage.all.filter { !activeKeys.contains($0.key) }
    }
}
