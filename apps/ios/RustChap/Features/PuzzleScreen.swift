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
        let deckCompleted: Bool
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
    @State private var showCostLegend = false

    private var puzzle: Puzzle { loaded.puzzle }

    // MARK: - Cost language (live preview; the outcomes table at Run is truth)

    private var optimalBudget: [String: Int]? {
        guard let scoring = puzzle.scoring, !scoring.optimal.isEmpty else { return nil }
        return scoring.optimal
    }

    private var goalNotation: String? {
        guard let scoring = puzzle.scoring, let budget = optimalBudget else { return nil }
        let text = CostLanguage.notation(budget, order: scoring.displayOrder)
        return text.isEmpty ? nil : text
    }

    private var liveCost: CostLanguage.LiveCost {
        CostLanguage.liveCost(
            puzzle: puzzle, selections: selections,
            blockOrder: blockOrder, chosenCandidate: chosenCandidate)
    }

    /// Meter letters = the goal chip's letters, in the same order.
    private var meterKeys: [String] {
        guard let scoring = puzzle.scoring, let budget = optimalBudget else { return [] }
        return CostLanguage.orderedKeys(budget, order: scoring.displayOrder)
    }

    private var atGoal: Bool {
        guard let budget = optimalBudget else { return false }
        let live = liveCost
        guard live.complete else { return false }
        return meterKeys.allSatisfy { key in
            guard CostLanguage.metric(key)?.live != false else { return true }
            return (live.counts[key] ?? 0) <= (budget[key] ?? 0)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(puzzle.goal)
                        .font(.callout)
                    if let goalNotation {
                        Spacer(minLength: 0)
                        Button {
                            showCostLegend = true
                        } label: {
                            Text("★ \(goalNotation)")
                                .font(.footnote.monospaced())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.yellow.opacity(0.12), in: Capsule())
                                .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
            Group {
                if puzzle.interaction.isLesson {
                    Button(action: completeLesson) {
                        Text("Got it")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 10) {
                        if !meterKeys.isEmpty {
                            costMeter
                        }
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
                    }
                }
            }
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
        .sheet(isPresented: $showCostLegend) {
            CostLegendSheet(activeKeys: Set(meterKeys))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: atGoal) { _, entered in
            entered // one soft tick when the meter first reaches the goal
        }
        .onAppear {
            resetToInitial()
            applyAutomationArguments()
        }
        .tutorButton {
            let record = ProgressRecorder.fetch(puzzleId: puzzle.id, in: modelContext)
            return .puzzle(
                loaded,
                concepts: store.concepts(for: puzzle),
                selections: selections,
                blockOrder: blockOrder,
                chosenCandidate: chosenCandidate,
                pastBest: record?.solved == true ? record?.bestRank : nil
            )
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
                selections: selections,
                via: presented.via,
                deckCompleted: presented.deckCompleted,
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
        case .lesson(let sections):
            Section {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    switch section {
                    case .prose(let text):
                        // LocalizedStringKey init: renders inline markdown, so
                        // lesson prose can mark types like `String` as code.
                        Text(.init(text))
                            .font(.callout)
                            .lineSpacing(3)
                            .listRowSeparator(.hidden)
                    case .code(let code, let caption):
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                CodeText(source: code)
                                    .padding(10)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            if let caption {
                                Text(caption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            }
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
        case .lesson:
            false
        }
    }

    /// The live cost pill next to Run: gray while picking, per-letter red
    /// when a budget is crossed, all green at the goal. Numbers never animate.
    private var costMeter: some View {
        let live = liveCost
        let budget = optimalBudget ?? [:]
        return Button {
            showCostLegend = true
        } label: {
            HStack(spacing: 3) {
                ForEach(Array(meterKeys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("·").foregroundStyle(.secondary)
                    }
                    if CostLanguage.metric(key)?.live == false {
                        Text("\(CostLanguage.letter(key))?")
                            .foregroundStyle(.secondary.opacity(0.6))
                    } else {
                        let value = live.counts[key] ?? 0
                        let over = value > (budget[key] ?? 0)
                        Text("\(value)\(CostLanguage.letter(key))")
                            .foregroundStyle(
                                atGoal ? .green : (over ? .red : .secondary))
                    }
                }
            }
            .font(.subheadline.monospaced())
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(atGoal ? Color.green.opacity(0.55) : .clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current cost; tap for the letter legend")
    }

    /// Lessons complete by reading: record, then move along the deck.
    private func completeLesson() {
        ProgressRecorder.record(
            in: modelContext, puzzle: puzzle,
            result: EvalResult(status: .solved, rank: .solved, metrics: [:], diagnostics: [])
        )
        if let nextId = store.nextPuzzleId(after: puzzle.id) {
            path = [.deck(puzzle.track), .puzzle(nextId)]
        } else {
            path = [.deck(puzzle.track)]
        }
        Task { await sync.syncNow() }
    }

    private func run() {
        let operations: [PuzzleOperation]
        switch puzzle.interaction {
        case .slotSelection(let slots), .minimalEdit(let slots):
            // Submit exactly this puzzle's slots — never whatever else the
            // selections dictionary has accumulated.
            operations = slots.compactMap { slot in
                selections[slot.id].map { .select(slotId: slot.id, choiceId: $0) }
            }
        case .blockArrangement:
            operations = [.arrange(order: blockOrder.map(\.id))]
        case .bestSolution:
            operations = [.pick(candidateId: chosenCandidate ?? "")]
        case .lesson:
            return // lessons complete via completeLesson(), never Run
        }
        evaluating = true
        Task {
            let (result, via) = await store.evaluate(loaded, operations: operations)
            errorSlotIds = result.status == .compileError
                ? Set(result.diagnostics.flatMap(\.slotIds))
                : []
            ProgressRecorder.record(in: modelContext, puzzle: puzzle, result: result)
            let deckCompleted = result.status == .solved
                && store.pack(containing: puzzle.id)?.puzzles.allSatisfy { loaded in
                    ProgressRecorder.fetch(puzzleId: loaded.id, in: modelContext)?.solved == true
                } == true
            presentedResult = PresentedResult(
                result: result, via: via, deckCompleted: deckCompleted)
            evaluating = false
            await sync.syncNow()
        }
    }
}
