import Foundation
import NaturalLanguage

/// One looked-up word, ready to show.
struct WordResult: Equatable, Identifiable {
    var id: String { headword }
    /// What the user copied, after cleaning ("Fled").
    let query: String
    /// Dictionary form ("flee"); equals `query` lowercased when nothing better was found.
    let headword: String
    let brief: BriefEntry?
    let atlas: AtlasEntry?
    /// Capitalised and unknown to both dictionaries: a name or a made-up word (Lannister).
    let isProperNoun: Bool

    var found: Bool { brief != nil || atlas != nil }

    var ipa: String? {
        if let ipa = atlas?.ipa, !ipa.isEmpty { return ipa }
        return brief?.phonetic.map { "/\($0)/" }
    }

    /// Brief level: one line per part of speech. Falls back to word-atlas senses for the
    /// 140 word-atlas words ECDICT lacks.
    var briefLines: [String] {
        if let lines = brief?.lines, !lines.isEmpty { return Array(lines.prefix(3)) }
        return atlas?.senses.map { "\($0.pos) \($0.zh)" } ?? []
    }
}

enum LookupResult: Equatable {
    case word(WordResult)
    /// A copied sentence, split into words the sentence view can mark in place.
    case sentence(text: String, tokens: [SentenceToken])
}

/// One word of a copied sentence, with the punctuation around it ("“fealty,”").
struct SentenceToken: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Function words, names, words not in the dictionary: shown, not tappable.
        case plain
        /// Common noun, verb, adjective or adverb: tappable, not highlighted.
        case content
        /// Outside the top 2000: highlighted.
        case hard
    }

    let id: Int
    let leading: String
    let surface: String
    let trailing: String
    /// No space before this token ("hall—and", "did|n't"), so it stays on the same line.
    let gluedToPrevious: Bool
    let word: WordResult?
    let kind: Kind
}

@MainActor
struct Lookup {
    /// Words ranked inside the top 2000 by frequency are "basic" (plan §2.1).
    static let basicRank = 2000

    let store: DictionaryStore

    func run(_ input: CleanedInput) -> LookupResult? {
        switch input {
        case .ignored:
            return nil
        case .word(let word):
            return .word(resolve(word))
        case .sentence(let text):
            return .sentence(text: text, tokens: tokens(in: text))
        }
    }

    func resolve(_ query: String) -> WordResult {
        let lower = query.lowercased()
        for candidate in candidates(for: query) {
            let brief = store.brief(candidate)
            let atlas = store.atlas(candidate.lowercased())
            if brief != nil || atlas != nil {
                return WordResult(query: query, headword: candidate, brief: brief, atlas: atlas, isProperNoun: false)
            }
        }
        let capitalised = query.first?.isUppercase == true
        return WordResult(query: query, headword: lower, brief: nil, atlas: nil, isProperNoun: capitalised)
    }

    /// Exact form first (keeps "Monday"), then lower case, then the inflection table
    /// (fled -> flee), then NaturalLanguage's lemma as a last resort.
    private func candidates(for query: String) -> [String] {
        let lower = query.lowercased()
        var out = [query, lower]
        out += store.lemmas(of: lower)
        if let lemma = nlLemma(lower) { out.append(lemma) }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    private func nlLemma(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        guard let lemma = tag?.rawValue.lowercased(), lemma != word else { return nil }
        return lemma
    }

    private func tokens(in text: String) -> [SentenceToken] {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var parts: [(range: Range<String.Index>, tag: NLTag?)] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            parts.append((range, tag))
            return true
        }

        var tokens: [SentenceToken] = []
        var leading = ""
        var glued = false
        for (i, part) in parts.enumerated() {
            // Text after this word up to the next one: punctuation before the first space
            // trails this word, the rest leads the next word.
            let gapEnd = i + 1 < parts.count ? parts[i + 1].range.lowerBound : text.endIndex
            let gap = text[part.range.upperBound..<gapEnd]
            let split = gap.firstIndex(where: \.isWhitespace)
            let trailing = String(gap[..<(split ?? gap.endIndex)])
            let surface = String(text[part.range])
            let (word, kind) = classify(surface, tag: part.tag, startsSentence: i == 0)
            tokens.append(SentenceToken(id: i, leading: leading, surface: surface, trailing: trailing,
                                        gluedToPrevious: glued, word: word, kind: kind))
            leading = split.map { String(gap[$0...].drop(while: \.isWhitespace)) } ?? ""
            glued = split == nil
        }
        return tokens
    }

    private static let contentClasses: Set<NLTag> = [.noun, .verb, .adjective, .adverb]
    private static let functionClasses: Set<NLTag> = [.determiner, .preposition, .pronoun, .conjunction,
                                                      .particle, .interjection]
    private static let nameTags: Set<NLTag> = [.personalName, .placeName, .organizationName]

    private func classify(_ surface: String, tag: NLTag?, startsSentence: Bool) -> (WordResult?, SentenceToken.Kind) {
        guard case .word(let query) = InputCleaner.clean(surface) else { return (nil, .plain) }
        // A capitalised name mid-sentence (Stark, Winterfell) is not a dictionary word here.
        if let tag, Self.nameTags.contains(tag), !startsSentence, surface.first?.isUppercase == true {
            return (nil, .plain)
        }
        let result = resolve(query)
        guard result.found, !result.isProperNoun else { return (nil, .plain) }
        if !isBasic(result) { return (result, .hard) }
        return isContentWord(result, tag: tag) ? (result, .content) : (nil, .plain)
    }

    /// ECDICT's first part of speech for words that are mostly grammar (the, of, his, would).
    private static let functionPOS: Set<String> = ["art.", "prep.", "pron.", "conj.", "aux.", "int."]

    /// The tagger's word class when it has one. Without its language model (the simulator)
    /// every word comes back as "other", so fall back to ECDICT's first part of speech;
    /// lines with no part of speech ("be的过去式") are forms of grammar words.
    private func isContentWord(_ result: WordResult, tag: NLTag?) -> Bool {
        if let tag, Self.contentClasses.contains(tag) { return true }
        if let tag, Self.functionClasses.contains(tag) { return false }
        guard let pos = result.briefLines.first?.split(separator: " ").first.map(String.init),
              pos.hasSuffix(".") else { return false }
        return !Self.functionPOS.contains(pos)
    }

    private func isBasic(_ result: WordResult) -> Bool {
        guard let rank = result.brief?.rank, rank > 0 else { return false }
        return rank <= Self.basicRank
    }
}
