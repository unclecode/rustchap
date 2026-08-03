// One skill lecture: the minimum a player needs to attempt the puzzle,
// Euclidea-style — a short read, not a course.

import SwiftUI

struct ConceptView: View {
    let concept: Concept

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(concept.summary)
                        .font(.callout.weight(.semibold))

                    ForEach(Array(concept.lecture.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.85))
                    }

                    if let example = concept.example {
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                CodeText(source: example.code)
                                    .padding(12)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            if let caption = example.caption {
                                Text(caption)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(concept.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
