import Foundation

/// ECDICT brief-level row (`entry` table).
struct BriefEntry: Equatable {
    let word: String
    let phonetic: String?
    /// One line per part of speech, e.g. "n. 骑士精神, 骑士制度".
    let lines: [String]
    /// Best of COCA / BNC frequency rank; 0 when unranked.
    let rank: Int
}

/// word-atlas mid-level row (`atlas` table). CC BY 4.0, Word Atlas contributors.
struct AtlasEntry: Equatable {
    struct Sense: Codable, Equatable { let pos: String; let zh: String; let en: String }
    struct Pair: Codable, Equatable { let en: String; let zh: String }

    let word: String
    let ipa: String?
    let senses: [Sense]
    let examples: [Pair]
    let collocations: [Pair]
    let family: [String]
    let synonyms: [String]
    let antonyms: [String]
    let tip: String?
    let note: String?
    let cefr: String?
    /// File name inside the bundled `thumb` folder.
    let image: String?
}

/// Just enough of a word-atlas entry to build quiz distractors.
struct AtlasStub: Equatable {
    let word: String
    let pos: String
    let zh: String
    let cefr: String
    let hasImage: Bool
}
