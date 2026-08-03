// Step-8 shell: working end-to-end loop with placeholder interaction
// controls (menus, move-to-reorder, candidate rows). The semantic code
// surface with tappable tokens replaces the preview + controls in steps 9-10.

import SwiftUI

struct PuzzleScreen: View {
    @Environment(ContentStore.self) private var store
    let loaded: ContentStore.LoadedPuzzle
    @Binding var path: [String]

    @State private var selections: [String: String] = [:]
    @State private var blockOrder: [Block] = []
    @State private var chosenCandidate: String?
    @State private var result: EvalResult?
    @State private var showResult = false
    @State private var showHints = false

    private var puzzle: Puzzle { loaded.puzzle }

    var body: some View {
        List {
            Section {
                Text(puzzle.goal)
                    .font(.callout)
            }

            Section("Code") {
                Text(codePreview)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            interactionSection

            if !puzzle.hints.isEmpty {
                Section {
                    DisclosureGroup("Hints", isExpanded: $showHints) {
                        ForEach(Array(puzzle.hints.enumerated()), id: \.offset) { _, hint in
                            Text(hint).font(.footnote)
                        }
                    }
                }
            }

            Section {
                Button(action: run) {
                    Text("Run")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canRun)
            }
        }
        .navigationTitle(puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: resetToInitial)
        .sheet(isPresented: $showResult) {
            if let result {
                ResultView(
                    loaded: loaded,
                    result: result,
                    nextPuzzleId: store.nextPuzzleId(after: puzzle.id),
                    onRetry: { showResult = false },
                    onNext: { nextId in
                        showResult = false
                        path = [nextId]
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Interaction placeholders

    @ViewBuilder
    private var interactionSection: some View {
        switch puzzle.interaction {
        case .slotSelection(let slots), .minimalEdit(let slots):
            Section("Fill the slots") {
                ForEach(slots) { slot in
                    Menu {
                        ForEach(slot.choices) { choice in
                            Button(choice.text) { selections[slot.id] = choice.id }
                        }
                    } label: {
                        HStack {
                            Text(slot.label ?? slot.id)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(selectedText(slot) ?? "choose…")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(selections[slot.id] == nil ? .orange : .primary)
                        }
                    }
                }
            }
        case .blockArrangement:
            Section("Order the blocks (drag to reorder)") {
                ForEach(blockOrder) { block in
                    Text(block.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(.body, design: .monospaced))
                }
                .onMove { from, to in
                    blockOrder.move(fromOffsets: from, toOffset: to)
                }
            }
            .environment(\.editMode, .constant(.active))
        case .bestSolution(let candidates):
            Section("Pick the best implementation") {
                ForEach(candidates) { candidate in
                    Button {
                        chosenCandidate = candidate.id
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: chosenCandidate == candidate.id
                                ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.tint)
                                .padding(.top, 2)
                            Text(candidate.code)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - State

    private func resetToInitial() {
        selections = [:]
        if case .minimalEdit(let slots) = puzzle.interaction {
            for slot in slots {
                if let original = slot.original,
                   let keep = slot.choices.first(where: { $0.text == original }) {
                    selections[slot.id] = keep.id
                }
            }
        }
        if case .blockArrangement(_, let blocks, _) = puzzle.interaction {
            blockOrder = blocks.reversed()
        }
        chosenCandidate = nil
    }

    private func selectedText(_ slot: Slot) -> String? {
        guard let choiceId = selections[slot.id] else { return nil }
        return slot.choices.first { $0.id == choiceId }?.text
    }

    private var codePreview: String {
        switch puzzle.interaction {
        case .slotSelection(let slots), .minimalEdit(let slots):
            var preview = puzzle.template ?? ""
            for slot in slots {
                let value = selectedText(slot) ?? "⟦\(slot.label ?? slot.id)⟧"
                preview = preview.replacingOccurrences(of: "⟦\(slot.id)⟧", with: value)
            }
            return preview
        case .blockArrangement(let prefix, _, let suffix):
            return prefix + blockOrder.map(\.text).joined() + suffix
        case .bestSolution(let candidates):
            guard let chosenCandidate,
                  let candidate = candidates.first(where: { $0.id == chosenCandidate })
            else { return "// pick a candidate below" }
            return candidate.code
        }
    }

    private var canRun: Bool {
        switch puzzle.interaction {
        case .slotSelection(let slots), .minimalEdit(let slots):
            slots.allSatisfy { selections[$0.id] != nil }
        case .blockArrangement:
            !blockOrder.isEmpty
        case .bestSolution:
            chosenCandidate != nil
        }
    }

    private func run() {
        let operations: [PuzzleOperation]
        switch puzzle.interaction {
        case .slotSelection, .minimalEdit:
            operations = selections.map { .select(slotId: $0.key, choiceId: $0.value) }
        case .blockArrangement:
            operations = [.arrange(order: blockOrder.map(\.id))]
        case .bestSolution:
            operations = [.pick(candidateId: chosenCandidate ?? "")]
        }
        result = LocalEvaluator(outcomes: loaded.outcomes).evaluate(operations)
            ?? EvalResult(
                status: .invalid, rank: nil, metrics: [:],
                diagnostics: [Diagnostic(
                    category: "missing_outcome",
                    message: "This submission is not in the precomputed outcomes — content bug.",
                    slotIds: [], rustCode: nil
                )]
            )
        showResult = true
    }
}
