// "Ask the tutor" — the on-device AI tutor sheet, reachable from every screen.
// Grounded per TutorService's rules; the entry button only exists when
// TutorAvailability says the model is usable (see .tutorButton()).

import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

struct TutorSheet: View {
    let context: TutorContext
    @State private var clearRequest = 0

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 26.0, *) {
                    TutorChatView(context: context, clearRequest: clearRequest)
                } else {
                    ContentUnavailableView(
                        "Tutor unavailable",
                        systemImage: "sparkles",
                        description: Text("The on-device tutor needs Apple Intelligence.")
                    )
                }
            }
            .navigationTitle(context.subject.map { "Ask about \($0)" } ?? "Ask the tutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        clearRequest += 1
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.large])
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private struct TutorChatView: View {
    let context: TutorContext
    /// Incremented by the sheet's "New chat" button.
    let clearRequest: Int

    @Environment(\.modelContext) private var modelContext
    @State private var messages: [TutorMessage] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var session: LanguageModelSession?
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        starterChips
                    }
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if thinking {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Thinking…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded {
                inputFocused = false
            })
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: messages.last?.text) { _, _ in
                // Streaming: follow the growing answer without animation churn.
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: thinking) { _, nowThinking in
                if nowThinking {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
        // Floating input capsule (the ChatGPT/Claude-app pattern): no
        // full-width bar — the sheet background runs edge-to-edge behind it,
        // so the keyboard's rounded corners sit against the main color with
        // no seam.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                TextField("Ask anything about this…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(thinking || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .onAppear {
            messages = TutorConversation.load(context.subjectId, in: modelContext)
        }
        .onChange(of: clearRequest) { _, _ in
            TutorConversation.clear(context.subjectId, in: modelContext)
            messages = []
            session = nil
            input = ""
        }
    }

    private var starterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Answers come from this puzzle's own material — offline, on your device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(context.suggested, id: \.self) { question in
                Button {
                    ask(question)
                } label: {
                    Text(question)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: TutorMessage) -> some View {
        switch message.role {
        case .player:
            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.18))
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .tutor:
            VStack(alignment: .leading, spacing: 8) {
                TutorMarkdown(text: message.text)
                CopyButton(text: message.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failure:
            Label(message.text, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !thinking else { return }
        input = ""
        ask(question)
    }

    private func ask(_ question: String) {
        messages.append(TutorMessage(role: .player, text: question))
        thinking = true
        Task {
            if session == nil {
                // Fresh session (first question, or resumed after relaunch):
                // fold the recent transcript in so the model keeps the thread.
                var instructions = context.instructions
                let replay = messages.dropLast().suffix(6).filter { $0.role != .failure }
                if !replay.isEmpty {
                    let turns = replay.map { message in
                        "\(message.role == .player ? "Player" : "Tutor"): \(message.text)"
                    }.joined(separator: "\n")
                    instructions += "\n\n# Recent conversation (continue it)\n\(turns)"
                }
                session = LanguageModelSession(instructions: instructions)
            }
            do {
                // Streamed cumulative snapshots: the answer bubble is created on
                // the first token and rewritten as it grows — the standard
                // Foundation Models pattern; SwiftUI diffs the re-render.
                var answerIndex: Int?
                for try await partial in session!.streamResponse(to: question) {
                    if let index = answerIndex {
                        messages[index].text = partial.content
                    } else {
                        thinking = false
                        messages.append(TutorMessage(role: .tutor, text: partial.content))
                        answerIndex = messages.count - 1
                    }
                }
            } catch {
                messages.append(TutorMessage(
                    role: .failure,
                    text: "The tutor couldn't answer that. Try a shorter question."
                ))
            }
            thinking = false
            TutorConversation.save(messages, subjectId: context.subjectId, in: modelContext)
        }
    }
}
#endif

/// Quiet per-message copy: raw markdown to the pasteboard, brief confirmation.
private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy message")
    }
}

// MARK: - Markdown rendering

/// Tutor answers as one selectable UITextView. UIKit, not SwiftUI Text:
/// `.textSelection` never engaged inside this sheet's scroll hierarchy, and
/// UITextView selection also works ACROSS blocks (paragraph → code), which
/// SwiftUI cannot do. Same small parser as before, drawn into a single
/// NSAttributedString with RustLexer colors for code. Model-output markdown
/// only — not a general engine.
struct TutorMarkdown: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = Self.render(text)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: UITextView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    // MARK: - Attributed rendering

    private enum MarkdownBlock {
        case paragraph(String)
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
    }

    static func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let body = UIFont.preferredFont(forTextStyle: .callout)
        let blocks = parse(text)

        for (index, block) in blocks.enumerated() {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 8
            switch block {
            case .paragraph(let content):
                result.append(inline(content, font: body, style: style))
            case .heading(let content):
                style.paragraphSpacingBefore = 4
                result.append(inline(content, font: bold(body), style: style))
            case .bullet(let content):
                style.headIndent = 14
                result.append(inline("•  " + content, font: body, style: style))
            case .numbered(let number, let content):
                style.headIndent = 18
                result.append(inline("\(number)  " + content, font: body, style: style))
            case .code(let source):
                style.paragraphSpacingBefore = 4
                style.firstLineHeadIndent = 8
                style.headIndent = 8
                let mono = UIFont.monospacedSystemFont(
                    ofSize: body.pointSize - 2, weight: .regular)
                for token in RustLexer.tokenize(source) {
                    result.append(NSAttributedString(string: token.text, attributes: [
                        .font: mono,
                        .foregroundColor: UIColor(token.kind.color),
                        .backgroundColor: UIColor.secondarySystemBackground,
                        .paragraphStyle: style,
                    ]))
                }
            }
            if index < blocks.count - 1 {
                result.append(NSAttributedString(
                    string: "\n", attributes: [.font: body, .paragraphStyle: style]))
            }
        }
        return result
    }

    /// Inline `code` spans, then **bold** and *italic* within the rest.
    private static func inline(
        _ text: String, font: UIFont, style: NSParagraphStyle
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let segments = text.components(separatedBy: "`")
        let codeFont = UIFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
        for (index, segment) in segments.enumerated() {
            // Odd segments sit between balanced backticks; an unbalanced
            // trailing marker falls through as plain text.
            if index % 2 == 1, segments.count % 2 == 1 {
                out.append(NSAttributedString(string: segment, attributes: [
                    .font: codeFont,
                    .foregroundColor: UIColor.label,
                    .backgroundColor: UIColor.secondarySystemBackground,
                    .paragraphStyle: style,
                ]))
            } else {
                out.append(emphasis(segment, font: font, style: style))
            }
        }
        return out
    }

    private static func emphasis(
        _ text: String, font: UIFont, style: NSParagraphStyle
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let boldParts = text.components(separatedBy: "**")
        for (index, part) in boldParts.enumerated() {
            let isBold = index % 2 == 1 && boldParts.count % 2 == 1
            let italicParts = part.components(separatedBy: "*")
            for (italicIndex, italicPart) in italicParts.enumerated() {
                let isItalic = italicIndex % 2 == 1 && italicParts.count % 2 == 1
                out.append(run(italicPart, font: font, bold: isBold, italic: isItalic, style: style))
            }
        }
        return out
    }

    private static func run(
        _ text: String, font: UIFont, bold isBold: Bool, italic: Bool, style: NSParagraphStyle
    ) -> NSAttributedString {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let styled: UIFont =
            if traits.isEmpty {
                font
            } else if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                UIFont(descriptor: descriptor, size: 0)
            } else {
                font
            }
        return NSAttributedString(string: text, attributes: [
            .font: styled,
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ])
    }

    private static func bold(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: 0)
    }

    private static func parse(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = codeLines {
                    result.append(.code(lines.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    flushParagraph()
                    codeLines = []
                }
                continue
            }
            if codeLines != nil {
                codeLines!.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("#") {
                flushParagraph()
                result.append(.heading(line.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."),
                      line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line.index(after: dot) < line.endIndex,
                      line[line.index(after: dot)] == " " {
                flushParagraph()
                result.append(.numbered(
                    String(line[...dot]),
                    line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
                ))
            } else {
                paragraph.append(line)
            }
        }
        // An unterminated fence still shows its code; trailing prose flushes.
        if let lines = codeLines {
            result.append(.code(lines.joined(separator: "\n")))
        }
        flushParagraph()
        return result
    }
}

/// Screenshot-automation affordance (`--md-preview`): the renderer against a
/// canned model-style answer, viewable without Foundation Models (simulator).
struct TutorMarkdownPreviewSheet: View {
    static let sample = """
    ## Why `&str` wins

    A `&String` parameter demands a **reference to an owning String**, while \
    `&str` is just a *view* — pointer plus length.

    - `&String` coerces to `&str` for free
    - string literals like `"hi"` are already `&str`
    - slices such as `&s[1..3]` also fit

    1. Own with `String`
    2. Lend with `&str`

    ```rust
    fn describe(text: &str) {
        println!("{}", text.trim());
    }
    ```
    The same instinct: take the view, not the container.
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                TutorMarkdown(text: Self.sample)
                    .padding()
            }
            .navigationTitle("Markdown preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Global entry point

/// "Available always, on tap": puts the tutor behind a toolbar sparkles
/// button on any screen. The button does not exist when the model is
/// unavailable — no dead affordances.
struct TutorButton: ViewModifier {
    let context: () -> TutorContext
    @State private var showTutor = false

    func body(content: Content) -> some View {
        if TutorAvailability.isAvailable {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showTutor = true
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        .accessibilityLabel("Ask the tutor")
                    }
                }
                .sheet(isPresented: $showTutor) {
                    TutorSheet(context: context())
                }
        } else {
            content
        }
    }
}

extension View {
    func tutorButton(context: @escaping () -> TutorContext) -> some View {
        modifier(TutorButton(context: context))
    }
}
