import Observation
import SwiftData
import SwiftUI

enum AppTab: Hashable { case lookup, history, cards }

@MainActor
@Observable
final class AppModel {
    var tab: AppTab = .lookup
    private(set) var current: LookupResult?
    /// The word tapped in a copied sentence; the sentence stays on screen above it.
    private(set) var picked: WordResult?
    /// The sentence the current word was picked from, saved as the card's Context.
    private(set) var currentContext: String?
    let watcher = ClipboardWatcher()

    @ObservationIgnored private let lookup: Lookup?
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        lookup = (try? DictionaryStore()).map(Lookup.init(store:))
        watcher.onText = { [weak self] text in
            guard let self, !UserDefaults.standard.bool(forKey: "capturePaused") else { return }
            // A word copied in the book always lands on the lookup tab.
            if self.handle(text) { self.tab = .lookup }
        }
    }

    var dictionaryMissing: Bool { lookup == nil }

    /// Entry point for every capture path: clipboard, drag and drop, paste button, history tap.
    /// Returns false when the text was ignored (URL, number, Chinese…).
    @discardableResult
    func handle(_ text: String) -> Bool {
        guard let lookup, let result = lookup.run(InputCleaner.clean(text)) else { return false }
        current = result
        picked = nil
        currentContext = nil
        if case .word(let word) = result, word.found {
            remember(word)
        }
        return true
    }

    /// Reopen a word from the history tab on the lookup tab.
    func reopen(_ headword: String) {
        handle(headword)
        tab = .lookup
    }

    /// First line of the brief level, for history rows.
    func briefLine(for headword: String) -> String {
        lookup?.resolve(headword).briefLines.first ?? ""
    }

    /// A word tapped in a copied sentence.
    func pick(_ word: WordResult, in sentence: String) {
        picked = word
        currentContext = sentence
        remember(word)
    }

    // MARK: Cards

    func card(for word: WordResult) -> StudyCard? {
        let headword = word.headword
        return try? context.fetch(FetchDescriptor<StudyCard>(predicate: #Predicate { $0.word == headword })).first
    }

    /// One-tap "加入卡片": meaning from the mid level when there is one, Source reused from last time.
    func addCard(for word: WordResult) {
        guard card(for: word) == nil else { return }
        let meaning = word.atlas.map { $0.senses.map { "\($0.pos) \($0.zh)" }.joined(separator: "；") }
            ?? word.briefLines.joined(separator: "；")
        let source = UserDefaults.standard.string(forKey: "lastSource") ?? ""
        context.insert(StudyCard(
            word: word.headword,
            meaning: meaning,
            rootFamily: word.atlas?.family.joined(separator: " · ") ?? "",
            source: source,
            imageName: word.atlas?.image,
            context: currentContext
        ))
        try? context.save()
    }

    // MARK: History

    private func remember(_ word: WordResult) {
        let headword = word.headword
        let existing = try? context.fetch(FetchDescriptor<LookupRecord>(
            predicate: #Predicate { $0.headword == headword }
        )).first
        if let existing {
            existing.lookedUpAt = .now
            existing.query = word.query
        } else {
            context.insert(LookupRecord(headword: headword, query: word.query))
        }
        try? context.save()
    }
}
