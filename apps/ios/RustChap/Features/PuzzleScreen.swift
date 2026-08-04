// The puzzle screen: goal, semantic code surface (tappable slot chips inside
// real highlighted code), interaction-specific controls, Run, result sheet.

import SwiftData
import SwiftUI

struct PuzzleScreen: View {
    @Environment(ContentStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var modelContext
    let loaded: ContentStore.LoadedPuzzle
    @Binding var path: [Route]

    struct PresentedResult: Identifiable {
        let id = UUID()
        let result: EvalResult
        let via: EvaluatedVia
    }

    @State private var selections: [String: String] = [:]
    @State private var blockOrder: [Block] = []
    @State private var chosenCandidate: String?
    @State private var activeSlot: Slot?
    @State private var showSkills = false
    @State private var showHints = false
    @State private var errorSlotIds: Set<String> = []
    @State private var presentedResult: PresentedResult?
    @State private var pendingNextId: String?
    @State private var pendingGoHome = false
    @State private var evaluating = false

    private var puzzle: Puzzle { loaded.puzzle }

    var body: some View {
        List {
            Section {
                Text(puzzle.goal)
                    .font(.callout)
            }

            interactionSection
        }
        .navigationTitle(puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !store.concepts(for: puzzle).isEmpty {
                    Button {
                        showSkills = true
                    } label: {
                        Image(systemName: "book.closed")
                    }
                }
                if !puzzle.hints.isEmpty {
                    Button {
                        showHints = true
                    } label: {
                        Image(systemName: "lightbulb")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: run) {
                Group {
                    if evaluating {
                        ProgressView()
                    } else {
                        Text("Run")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRun || evaluating)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
        .sheet(isPresented: $showSkills) {
            SkillsSheet(concepts: store.concepts(for: puzzle))
        }
        .sheet(isPresented: $showHints) {
            HintsSheet(hints: puzzle.hints)
        }
        .onAppear {
            resetToInitial()
            applyAutomationArguments()
        }
        .sensoryFeedback(trigger: presentedResult?.id) { _, _ in
            guard let presented = presentedResult else { return nil }
            return presented.result.status == .solved ? .success : .error
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
                    path = [.deck(puzzle.track), .puzzle(nextId)]
                } else if pendingGoHome {
                    pendingGoHome = false
                    path = []
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
                },
                onDeckComplete: {
                    pendingGoHome = true
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

    // MARK: - Automation (simulator screenshot scripts)

    /// `--choose arg=c2,param_ty=t3` pre-applies slot selections;
    /// `--autorun` submits once the screen appears.
    private func applyAutomationArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--choose"), args.indices.contains(flag + 1) {
            for pair in args[flag + 1].split(separator: ",") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    selections[String(parts[0])] = String(parts[1])
                }
            }
        }
        if args.contains("--autorun"), canRun {
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                run()
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
            ProgressRecorder.record(in: modelContext, puzzle: puzzle, result: result)
            presentedResult = PresentedResult(result: result, via: via)
            evaluating = false
            await sync.syncNow()
        }
    }
}
