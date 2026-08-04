// Skill lectures: the minimum a player needs to attempt the puzzle,
// Euclidea-style — a short read, not a course.

import SwiftUI

/// The lecture content, embeddable anywhere (skills sheet pushes it).
struct ConceptLectureView: View {
    let concept: Concept

    var body: some View {
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
}

/// Round gray ✕ — the HIG-standard dismiss control for informational sheets.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .accessibilityLabel("Close")
    }
}

/// Toolbar entry point: the puzzle's skills as a browsable sheet.
struct SkillsSheet: View {
    let concepts: [Concept]

    var body: some View {
        NavigationStack {
            List(concepts) { concept in
                NavigationLink(value: concept) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(concept.title)
                            .font(.subheadline.weight(.medium))
                        Text(concept.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .navigationDestination(for: Concept.self) { concept in
                ConceptLectureView(concept: concept)
            }
            .navigationTitle("Skills for this puzzle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Hints as a compact sheet.
struct HintsSheet: View {
    let hints: [String]

    var body: some View {
        NavigationStack {
            List(Array(hints.enumerated()), id: \.offset) { index, hint in
                Label(hint, systemImage: "\(index + 1).circle")
                    .font(.subheadline)
            }
            .navigationTitle("Hints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
