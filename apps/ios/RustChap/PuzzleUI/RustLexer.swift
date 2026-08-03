// Display-side tokenizer for the code surface. Deliberately approximate:
// it colors tokens, it never decides meaning — reconstruction and evaluation
// stay in the Rust engine. Handles the subset our templates use.

import Foundation

enum TokenKind {
    case keyword, type, string, number, macro, comment, lifetime, identifier, punctuation, plain
}

struct CodeToken {
    let text: String
    let kind: TokenKind
}

enum RustLexer {
    private static let keywords: Set<String> = [
        "fn", "let", "mut", "if", "else", "for", "while", "loop", "match", "return",
        "use", "pub", "struct", "enum", "impl", "trait", "where", "in", "ref", "move",
        "async", "await", "dyn", "unsafe", "as", "const", "static", "crate", "mod",
        "self", "true", "false",
    ]
    private static let primitives: Set<String> = [
        "str", "i8", "i16", "i32", "i64", "i128", "u8", "u16", "u32", "u64", "u128",
        "usize", "isize", "f32", "f64", "bool", "char",
    ]

    static func tokenize(_ source: String) -> [CodeToken] {
        var tokens: [CodeToken] = []
        let chars = Array(source)
        var i = 0

        func take(while predicate: (Character) -> Bool) -> String {
            var text = ""
            while i < chars.count, predicate(chars[i]) {
                text.append(chars[i])
                i += 1
            }
            return text
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" {
                tokens.append(CodeToken(text: "\n", kind: .plain))
                i += 1
            } else if c == " " {
                tokens.append(CodeToken(text: take(while: { $0 == " " }), kind: .plain))
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                tokens.append(CodeToken(text: take(while: { $0 != "\n" }), kind: .comment))
            } else if c == "\"" {
                var text = String(chars[i]); i += 1
                while i < chars.count {
                    let ch = chars[i]
                    text.append(ch); i += 1
                    if ch == "\\", i < chars.count { text.append(chars[i]); i += 1 } else if ch == "\"" { break }
                }
                tokens.append(CodeToken(text: text, kind: .string))
            } else if c == "'", i + 1 < chars.count, chars[i + 1].isLetter || chars[i + 1] == "_" {
                i += 1
                let name = take(while: { $0.isLetter || $0.isNumber || $0 == "_" })
                tokens.append(CodeToken(text: "'" + name, kind: .lifetime))
            } else if c.isLetter || c == "_" {
                let word = take(while: { $0.isLetter || $0.isNumber || $0 == "_" })
                if i < chars.count, chars[i] == "!" {
                    i += 1
                    tokens.append(CodeToken(text: word + "!", kind: .macro))
                } else if keywords.contains(word) {
                    tokens.append(CodeToken(text: word, kind: .keyword))
                } else if primitives.contains(word) || (word.first?.isUppercase ?? false) {
                    tokens.append(CodeToken(text: word, kind: .type))
                } else {
                    tokens.append(CodeToken(text: word, kind: .identifier))
                }
            } else if c.isNumber {
                tokens.append(CodeToken(
                    text: take(while: { $0.isNumber || $0.isLetter || $0 == "_" }),
                    kind: .number
                ))
            } else {
                tokens.append(CodeToken(text: String(c), kind: .punctuation))
                i += 1
            }
        }
        return tokens
    }
}

// MARK: - Template → renderable lines

/// One inline element of a rendered code line: a colored token or a slot chip.
enum LineElement {
    case token(CodeToken)
    case slot(Slot)
}

enum CodeLineBuilder {
    /// Split a template on ⟦slot⟧ markers, lex the static parts, and fold the
    /// stream into lines for the interactive surface.
    static func lines(template: String, slots: [Slot]) -> [[LineElement]] {
        var lines: [[LineElement]] = [[]]
        for segment in segments(of: template) {
            switch segment {
            case .slot(let id):
                if let slot = slots.first(where: { $0.id == id }) {
                    lines[lines.count - 1].append(.slot(slot))
                }
            case .text(let text):
                for token in RustLexer.tokenize(text) {
                    if token.text == "\n" {
                        lines.append([])
                    } else {
                        lines[lines.count - 1].append(.token(token))
                    }
                }
            }
        }
        return lines
    }

    private enum Segment {
        case text(String)
        case slot(String)
    }

    private static func segments(of template: String) -> [Segment] {
        var result: [Segment] = []
        var current = ""
        var slotId: String?
        for ch in template {
            switch (ch, slotId) {
            case ("⟦", _):
                if !current.isEmpty { result.append(.text(current)); current = "" }
                slotId = ""
            case ("⟧", .some(let id)):
                result.append(.slot(id))
                slotId = nil
            case (_, .some):
                slotId?.append(ch)
            case (_, nil):
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(.text(current)) }
        return result
    }
}
