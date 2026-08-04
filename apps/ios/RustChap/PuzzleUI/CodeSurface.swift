// The semantic code surface: code rendered as native colored tokens with
// inline tappable slot chips. Never wraps — horizontal scroll preserves the
// shape of the code.

import SwiftUI

extension TokenKind {
    var color: Color {
        switch self {
        case .keyword: .purple
        case .type: .teal
        case .string: .orange
        case .number: .mint
        case .macro: .indigo
        case .comment: .secondary
        case .lifetime: .pink
        case .identifier: .primary
        case .punctuation: .secondary
        case .plain: .primary
        }
    }
}

let codeFont = Font.system(size: 14, design: .monospaced)

/// Static highlighted code (candidate cards, block rows, prefix/suffix lines).
struct CodeText: View {
    let source: String

    var body: some View {
        RustLexer.tokenize(source).reduce(Text(verbatim: "")) { acc, token in
            acc + Text(verbatim: token.text).foregroundColor(token.kind.color)
        }
        .font(codeFont)
    }
}

/// Interactive surface for slot puzzles: colored token lines with tappable
/// chips where the ⟦slots⟧ are.
struct CodeSurface: View {
    let lines: [[LineElement]]
    let selections: [String: String]
    let errorSlotIds: Set<String>
    let onTapSlot: (Slot) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines.indices, id: \.self) { lineIndex in
                    HStack(spacing: 0) {
                        ForEach(lines[lineIndex].indices, id: \.self) { elementIndex in
                            element(lines[lineIndex][elementIndex])
                        }
                    }
                    .frame(minHeight: 22)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func element(_ element: LineElement) -> some View {
        switch element {
        case .token(let token):
            Text(verbatim: token.text)
                .font(codeFont)
                .foregroundStyle(token.kind.color)
        case .slot(let slot):
            SlotChip(
                slot: slot,
                selectedText: selections[slot.id].flatMap { id in
                    slot.choices.first { $0.id == id }?.text
                },
                isError: errorSlotIds.contains(slot.id)
            ) {
                onTapSlot(slot)
            }
            .padding(.horizontal, 2)
        }
    }
}

/// One editable token: filled (chosen value) or empty (dashed placeholder).
struct SlotChip: View {
    let slot: Slot
    let selectedText: String?
    let isError: Bool
    let action: () -> Void

    private var filled: Bool { selectedText != nil }

    var body: some View {
        Button(action: action) {
            Text(verbatim: selectedText ?? (slot.label ?? slot.id))
                .font(codeFont.weight(.medium))
                .foregroundStyle(chipForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(chipBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            chipBorder,
                            style: StrokeStyle(lineWidth: 1.2, dash: filled ? [] : [4, 3])
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var chipForeground: Color {
        if isError { .red }
        else if filled { .accentColor }
        else { .secondary }
    }

    private var chipBackground: Color {
        if isError { .red.opacity(0.10) }
        else if filled { .accentColor.opacity(0.12) }
        else { .secondary.opacity(0.06) }
    }

    private var chipBorder: Color {
        if isError { .red }
        else if filled { .accentColor.opacity(0.55) }
        else { .secondary.opacity(0.5) }
    }
}

/// Bottom tray listing a slot's choices as code.
struct ChoiceTray: View {
    let slot: Slot
    let selectedChoiceId: String?
    let onSelect: (Choice) -> Void

    var body: some View {
        NavigationStack {
            List(slot.choices) { choice in
                Button {
                    onSelect(choice)
                } label: {
                    HStack {
                        CodeText(source: choice.text)
                        Spacer()
                        if choice.id == selectedChoiceId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(slot.label ?? slot.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.height(CGFloat(140 + slot.choices.count * 52))])
        .presentationDragIndicator(.visible)
    }
}
