import Foundation

/// Parsed representation of a user search query.
public struct ParsedSearchQuery {
    public struct Part: Equatable {
        public let text: String      // sanitized text (for phrases it preserves inner spaces)
        public let isPhrase: Bool    // true if originally quoted with "..."
        public let op: Operator      // logical operator preceding this part
    }
    public enum Operator: Equatable {
        case and    // default
        case or
        case not
    }
    public let parts: [Part]
}

/// Lightweight parser that understands:
/// - quoted phrases: "hello world" kept verbatim and matched exactly
/// - normal tokens: split by whitespace
/// - boolean operators: AND, OR, NOT (case-insensitive)
/// - sanitization: keep only alphanumerics and spaces inside phrases
struct SearchQueryParser {
    private static let operatorKeywords: Set<String> = ["and", "or", "not"]

    static func parse(_ raw: String) -> ParsedSearchQuery {
        var i = raw.startIndex
        var parts: [ParsedSearchQuery.Part] = []
        var nextOp: ParsedSearchQuery.Operator = .and

        func sanitizeToken(_ s: Substring) -> String {
            let scalars = s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            return String(String.UnicodeScalarView(scalars))
        }

        while i < raw.endIndex {
            // Skip whitespace
            if raw[i].isWhitespace { i = raw.index(after: i); continue }
            let c = raw[i]
            if c == "\"" { // phrase
                var j = raw.index(after: i)
                var phraseEnded = false
                while j < raw.endIndex {
                    if raw[j] == "\"" { phraseEnded = true; break }
                    j = raw.index(after: j)
                }
                let inner = raw.index(after: i)..<j
                let sanitized = sanitizePhrase(raw[inner])
                if !sanitized.isEmpty {
                    parts.append(.init(text: sanitized, isPhrase: true, op: nextOp))
                    nextOp = .and // reset to default
                }
                i = phraseEnded ? raw.index(after: j) : j
            } else { // token
                var j = i
                while j < raw.endIndex && !raw[j].isWhitespace { j = raw.index(after: j) }
                let tokenStr = String(raw[i..<j]).lowercased()

                // Check if this token is a boolean operator
                if tokenStr == "and" {
                    nextOp = .and
                } else if tokenStr == "or" {
                    nextOp = .or
                } else if tokenStr == "not" || tokenStr == "-" {
                    nextOp = .not
                } else {
                    let sanitized = sanitizeToken(Substring(tokenStr))
                    if !sanitized.isEmpty {
                        parts.append(.init(text: sanitized, isPhrase: false, op: nextOp))
                        nextOp = .and // reset to default
                    }
                }
                i = j
            }
        }
        return ParsedSearchQuery(parts: parts)
    }

    private static func sanitizePhrase(_ s: Substring) -> String {
        let scalars = s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        let collapsed = String(String.UnicodeScalarView(scalars)).replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
