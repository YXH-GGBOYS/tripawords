import Testing
@testable import FoldPilot

struct InputCleanerTests {
    @Test(arguments: [
        ("chivalry", "chivalry"),
        ("  “Chivalry,” ", "Chivalry"),
        ("knights.", "knights"),
        ("Ned\u{2019}s", "Ned"),
        ("well-known", "well-known"),
        ("(fled)", "fled"),
    ])
    func singleWords(raw: String, expected: String) {
        #expect(InputCleaner.clean(raw) == .word(expected))
    }

    @Test(arguments: ["", "   ", "1220", "https://example.com/a", "www.example.com", "骑士精神", "chivalry 骑士", "abc123", "£20"])
    func ignored(raw: String) {
        #expect(InputCleaner.clean(raw) == .ignored)
    }

    @Test func sentence() {
        let raw = "\"The ideals of chivalry were\n popularized in medieval literature.\""
        #expect(InputCleaner.clean(raw) == .sentence("The ideals of chivalry were popularized in medieval literature"))
    }
}

@MainActor
struct LookupTests {
    let lookup = Lookup(store: try! DictionaryStore())

    @Test(arguments: [("fled", "flee"), ("knights", "knight"), ("Swore", "swear"), ("courtiers", "courtier"), ("chivalry", "chivalry")])
    func lemmatizes(query: String, headword: String) {
        let result = lookup.resolve(query)
        #expect(result.headword == headword)
        #expect(result.found)
    }

    @Test func atlasWordHasMidLevelAndImage() throws {
        let result = lookup.resolve("treason")
        let atlas = try #require(result.atlas)
        #expect(atlas.senses.first?.zh == "叛国罪")
        #expect(atlas.image == "treason.webp")
        #expect(result.ipa == "/ˈtriːzən/")
    }

    @Test func properNoun() {
        let result = lookup.resolve("Lannister")
        #expect(result.isProperNoun)
        #expect(!result.found)
    }

    @Test func capitalisedCommonWordIsNotAName() {
        #expect(!lookup.resolve("Fled").isProperNoun)
    }

    @Test func sentenceMarksWordsInPlace() throws {
        let text = "The knight knelt before the queen and swore an oath of fealty, his voice trembling in the cold hall"
        guard case .sentence(_, let tokens) = try #require(lookup.run(.sentence(text)))
        else { Issue.record("expected a sentence result"); return }
        func heads(_ kind: SentenceToken.Kind) -> Set<String> {
            Set(tokens.filter { $0.kind == kind }.compactMap { $0.word?.headword })
        }
        // ECDICT lists "trembling" as an adjective of its own, so it stays as copied.
        #expect(heads(.hard) == ["knight", "kneel", "swear", "oath", "fealty", "trembling"])
        #expect(heads(.content).isSuperset(of: ["queen", "voice", "hall"]))
        let plain = Set(tokens.filter { $0.kind == .plain }.map { $0.surface.lowercased() })
        #expect(plain.isSuperset(of: ["the", "before", "and", "an", "of", "his", "in"]))
        // Punctuation stays attached, and the sentence reads back unchanged.
        #expect(tokens.first { $0.surface == "fealty" }?.trailing == ",")
        let rebuilt = tokens.map { ($0.gluedToPrevious ? "" : " ") + $0.leading + $0.surface + $0.trailing }.joined()
        #expect(rebuilt.dropFirst() == text)
    }

    @Test func sentenceSkipsNames() throws {
        guard case .sentence(_, let tokens) = try #require(lookup.run(.sentence("Lord Stark rode north to Winterfell")))
        else { Issue.record("expected a sentence result"); return }
        #expect(tokens.first { $0.surface == "Winterfell" }?.kind == .plain)
    }
}
