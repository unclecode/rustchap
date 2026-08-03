// The puzzle screen: goal, semantic code surface (tappable slot chips inside
// real highlighted code), interaction-specific controls, Run, result sheet.

import SwiftUI

struct PuzzleScreen: View {
    @Environment(ContentStore.self) private var store
    let loaded: ContentStore.LoadedPuzzle
    @Binding var path: [String]

    struct PresentedResult: Identifiable {
        let id = UUID()
        let result: EvalResult
        let via: EvaluatedVia
    }

    @State private var selections: [String: String] = [:]
    @State private var blockOrder: [Block] = []
    @State private var chosenCandidate: String?
    @State private var activeSlot: Slot?
    @State private var activeConcept: Concept?
    @State private var errorSlotIds: Set<String> = []
    @State private var presentedResult: PresentedResult?
    @State private var pendingNextId: String?
    @State private var showHints = false
    @State private var evaluating = false

    private var puzzle: Puzzle { loaded.puzzle }

    var body: some View {
        List {
            Section {
                Text(puzzle.goal)
                    .font(.callout)
            }

            interactionSection

            let skills = store.concepts(for: puzzle)
            if !skills.isEmpty {
                Section("Skills for this puzzle") {
                    ForEach(skills) { concept in
                        Button {
                            activeConcept = concept
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(concept.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(concept.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

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
                    if evaluating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Run")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canRun || evaluating)
            }
        }
        .navigationTitle(puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            resetToInitial()
            // Screenshot automation: submit the initial state right away.
            if ProcessInfo.processInfo.arguments.contains("--autorun"), canRun {
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    run()
                }
            }
        }
        .sensoryFeedback(trigger: presentedResult?.id) { _, _ in
            guard let presented = presentedResult else { return nil }
            return presented.result.status == .solved ? .success : .error
        }
        .sheet(item: $activeConcept) { concept in
            ConceptView(concept: concept)
        }
        .sheet(item: $activeSlot) { slot in
            ChoiceTray(slot: slot, selectedChoiceId: selections[slot.id]) { choice in
                selections[slot.id] = choice.id
                errorSlotIds = []
                activeSlot = nil
            }
        }
        .sheet(
            item: $presentedResult,
            onDismiss: {
                // Navigating while the sheet is still dismissing gets silently
                // dropped by NavigationStack — defer the push until it's gone.
                if let nextId = pendingNextId {
                    pendingNextId = nil
                    path = [nextId]
                }
            }
        ) { presented in
            ResultView(
                loaded: loaded,
                result: presented.result,
                via: presented.via,
                nextPuzzleId: store.nextPuzzleId(after: puzzle.id),
                onRetry: { presentedResult = nil },
                onNext: { nextId in
                    pendingNextId = nextId
                    presentedResult = nil
                }
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Interactions

    @ViewBuilder
    private var interactionSection: some View {
        switch puzzle.interaction {
        case .slotSelection(let slots), .minimalEdit(let slots):
            Section {
                CodeSurface(
                    lines: CodeLineBuilder.lines(template: puzzle.template ?? "", slots: slots),
                    selections: selections,
                    errorSlotIds: errorSlotIds,
                    onTapSlot: { activeSlot = $0 }
                )
            } header: {
                Text("Tap the highlighted tokens")
            }
        case .blockArrangement(let prefix, _, let suffix):
            Section("Drag the blocks into order") {
                CodeText(source: prefix)
                ForEach(blockOrder) { block in
                    HStack {
                        CodeText(source: block.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .padding(.leading, 16)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                    }
                }
                .onMove { from, to in
                    blockOrder.move(fromOffsets: from, toOffset: to)
                }
                CodeText(source: suffix.trimmingCharacters(in: .newlines))
            }
            .environment(\.editMode, .constant(.active))
        case .bestSolution(let candidates):
            Section("Pick the best implementation") {
                ForEach(candidates) { candidate in
                    Button {
                        chosenCandidate = candidate.id
                    } label: {
                        ScrollView(.horizontal, showsIndicators: false) {
                            CodeText(source: candidate.code)
                                .padding(10)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    chosenCandidate == candidate.id ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    // MARK: - State

    private func resetToInitial() {
        selections = [:]
        errorSlotIds = []
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
        evaluating = true
        Task {
            let (result, via) = await store.evaluate(loaded, operations: operations)
            errorSlotIds = result.status == .compileError
                ? Set(result.diagnostics.flatMap(\.slotIds))
                : []
            presentedResult = PresentedResult(result: result, via: via)
            evaluating = false
        }
    }
}
