import Foundation

/// What a piece of copied text should turn into.
enum CleanedInput: Equatable {
    case word(String)
    case sentence(String)
    case ignored
}

/// Turns raw clipboard text into a lookup request (plan §4.1): trims punctuation and quotes,
/// ignores URLs, numbers and Chinese, and tells single words from sentences.
enum InputCleaner {
    static let maxLength = 600

    private static let edgeTrim = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
    // Computed: Regex is not Sendable, so it cannot be a stored static.
    private static var wordPattern: Regex<Substring> { #/^[A-Za-z]+(?:[-'][A-Za-z]+)*$/# }

    static func clean(_ raw: String) -> CleanedInput {
        let text = raw
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: edgeTrim)
        guard !text.isEmpty, text.count <= maxLength else { return .ignored }
        guard !containsHan(text), !looksLikeURL(text) else { return .ignored }
        guard text.contains(where: \.isLetter) else { return .ignored }

        if text.wholeMatch(of: wordPattern) != nil {
            return .word(stripPossessive(text))
        }
        if text.contains(where: \.isWhitespace) {
            return .sentence(text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " "))
        }
        return .ignored
    }

    private static func stripPossessive(_ word: String) -> String {
        word.hasSuffix("'s") && word.count > 3 ? String(word.dropLast(2)) : word
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic }
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
            return true
        }
        return !text.contains(" ") && text.contains(".") && text.contains("/")
    }
}
