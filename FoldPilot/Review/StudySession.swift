import Foundation
import FSRS
import Observation

// Study flow and quiz types adapted from word-atlas `src/store/session.ts`
// (https://github.com/designfuchen/word-atlas, MIT). Applies only to cards whose word is in
// word-atlas; every other card is a flip card rated by hand.

enum QuizKind: Equatable, CaseIterable {
    /// English word shown, pick the Chinese meaning.
    case meaning
    /// Illustration and a gapped example sentence, pick the English word.
    case picture
    /// Hear the word, pick it.
    case listen
    /// Illustration and meaning shown, type the word.
    case spell
}

struct Choice: Equatable, Identifiable {
    var id: String { word }
    let word: String
    let label: String
}

struct StudyStep: Identifiable, Equatable {
    enum Kind: Equatable {
        /// First meeting with a new word: show everything, no grading.
        case intro
        case quiz(QuizKind)
        case flip
    }

    let id = UUID()
    let word: String
    let kind: Kind
    var choices: [Choice] = []
    /// Example sentence with the word blanked, for `.picture`.
    var cloze: String?
    var isRetry = false
}

/// Deterministic 32-bit FNV-1a, so quiz picks are stable within a session and in tests.
func fnv1a(_ s: String) -> UInt32 {
    var h: UInt32 = 2_166_136_261
    for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
    return h
}

enum QuizRules {
    /// word-atlas `gradeFor`: wrong = Again; hinted or slow = Hard; a fast correct spelling = Easy.
    static func grade(kind: QuizKind, correct: Bool, elapsed: Duration, hinted: Bool) -> Rating {
        guard correct else { return .again }
        if hinted { return .hard }
        let slow: Duration = kind == .spell ? .seconds(20) : .seconds(9)
        let fast: Duration = kind == .spell ? .seconds(6) : .milliseconds(2500)
        if elapsed > slow { return .hard }
        if kind == .spell, elapsed < fast { return .easy }
        return .good
    }

    /// word-atlas `quizKind`: easy recognition while the memory is weak, recall once it holds.
    static func kind(stability: Double, hasImage: Bool, hasCloze: Bool, salt: String) -> QuizKind {
        let roll = Int(fnv1a(salt) % 100)
        let picture = hasImage && hasCloze
        if stability < 2 {
            if picture, roll < 45 { return .picture }
            return roll < 80 ? .meaning : .listen
        }
        if stability >= 4 || roll < 35 {
            return roll < 75 ? .spell : picture ? .picture : .listen
        }
        return roll < 50 ? .listen : picture ? .picture : .meaning
    }

    /// Plausible wrong answers: same level or part of speech for meaning questions, similar
    /// spelling and length for word questions, never a word that shares the core meaning.
    static func choices(for target: AtlasStub, kind: QuizKind, pool: [AtlasStub], seed: String) -> [Choice] {
        let core = target.zh.split(whereSeparator: { "；;，,".contains($0) }).first.map(String.init) ?? target.zh
        let word = target.word.lowercased()
        var scored: [(Int, AtlasStub)] = []
        for w in pool where w.word.lowercased() != word {
            if !core.isEmpty, w.zh.contains(core) { continue }
            var score = Int(fnv1a(w.word + seed) % 100)
            if kind == .meaning {
                if w.cefr == target.cefr { score += 40 }
                if w.pos == target.pos { score += 60 }
            } else {
                if w.word.first?.lowercased() == word.first.map(String.init) { score += 120 }
                score += max(0, 60 - abs(w.word.count - word.count) * 20)
            }
            scored.append((score, w))
        }
        scored.sort { $0.0 > $1.0 }
        var seen: Set<String> = [kind == .meaning ? target.zh : word]
        var picks: [AtlasStub] = [target]
        for (_, w) in scored {
            let key = kind == .meaning ? w.zh : w.word.lowercased()
            guard seen.insert(key).inserted else { continue }
            picks.append(w)
            if picks.count == 4 { break }
        }
        let label: (AtlasStub) -> String = { kind == .meaning ? "\($0.pos) \($0.zh)" : $0.word }
        return picks
            .map { Choice(word: $0.word, label: label($0)) }
            .sorted { fnv1a($0.word + seed) < fnv1a($1.word + seed) }
    }

    /// The example sentence with the word (or an inflection of it) replaced by a blank.
    static func cloze(_ sentence: String, word: String) -> String? {
        let stem = word.count > 4 ? String(word.dropLast(word.hasSuffix("e") || word.hasSuffix("y") ? 1 : 0)) : word
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: stem))[a-z]*\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(sentence.startIndex..., in: sentence)
        guard regex.firstMatch(in: sentence, range: range) != nil else { return nil }
        return regex.stringByReplacingMatches(in: sentence, range: range, withTemplate: "_____")
    }
}

/// One study sitting: reviews first while attention is fresh, then new words five at a time
/// (meet them, then recall them in a different order). Only the first answer to a word in a
/// sitting changes its schedule; a wrong answer brings the word back a few steps later as a
/// different question type, at most twice.
@MainActor
@Observable
final class StudySession {
    static let groupSize = 5
    static let maxRetries = 2

    private(set) var steps: [StudyStep] = []
    private(set) var index = 0
    private(set) var cards: [String: StudyCard] = [:]

    @ObservationIgnored private let scheduler: ReviewScheduler
    @ObservationIgnored private let store: DictionaryStore?
    @ObservationIgnored private var graded: Set<String> = []
    @ObservationIgnored private var retries: [String: Int] = [:]
    @ObservationIgnored private let seed = String(Int(Date().timeIntervalSince1970))

    var current: StudyStep? { index < steps.count ? steps[index] : nil }
    var progress: (done: Int, total: Int) { (index, steps.count) }

    init(scheduler: ReviewScheduler, store: DictionaryStore?, now: Date = .now) {
        self.scheduler = scheduler
        self.store = store
        let reviews = scheduler.dueToday(now: now, limit: 120)
        let fresh = scheduler.newToday(now: now, limit: nil)
        for card in reviews + fresh { cards[card.word] = card }

        for (i, card) in reviews.enumerated() {
            steps.append(quizOrFlip(card, salt: "r\(i)"))
        }
        for start in stride(from: 0, to: fresh.count, by: Self.groupSize) {
            let group = Array(fresh[start..<min(start + Self.groupSize, fresh.count)])
            let quizzable = group.filter { atlasEntry($0.word) != nil }
            for card in group where atlasEntry(card.word) == nil {
                steps.append(StudyStep(word: card.word, kind: .flip))
            }
            for card in quizzable { steps.append(StudyStep(word: card.word, kind: .intro)) }
            for (i, card) in quizzable.sorted(by: { fnv1a($0.word + seed) < fnv1a($1.word + seed) }).enumerated() {
                steps.append(quizOrFlip(card, salt: "n\(start + i)"))
            }
        }
    }

    func atlasEntry(_ word: String) -> AtlasEntry? { store?.atlas(word) }

    func continueFromIntro() { index += 1 }

    func answerFlip(_ answer: ReviewAnswer) {
        guard let step = current, let card = cards[step.word] else { return }
        scheduler.answer(card, with: answer)
        index += 1
    }

    func answerQuiz(correct: Bool, elapsed: Duration, hinted: Bool) {
        guard let step = current, case .quiz(let kind) = step.kind, let card = cards[step.word] else { return }
        if graded.insert(step.word).inserted {
            scheduler.apply(QuizRules.grade(kind: kind, correct: correct, elapsed: elapsed, hinted: hinted), to: card)
        }
        if !correct, retries[step.word, default: 0] < Self.maxRetries {
            retries[step.word, default: 0] += 1
            var retry = quizOrFlip(card, salt: "x\(index)", avoiding: kind)
            retry.isRetry = true
            steps.insert(retry, at: min(index + 4, steps.count))
        }
        index += 1
    }

    private func quizOrFlip(_ card: StudyCard, salt: String, avoiding: QuizKind? = nil) -> StudyStep {
        guard let atlas = atlasEntry(card.word),
              let neighbors = store?.atlasNeighbors(of: atlas.word),
              let me = neighbors.words.first(where: { $0.word == atlas.word })
        else { return StudyStep(word: card.word, kind: .flip) }

        let cloze = atlas.examples.lazy.compactMap { QuizRules.cloze($0.en, word: atlas.word) }.first
        var kind = QuizRules.kind(stability: card.fsrsCard.stability, hasImage: atlas.image != nil,
                                  hasCloze: cloze != nil, salt: card.word + seed + salt)
        if kind == avoiding {
            kind = kind == .meaning ? .listen : .meaning
        }
        var step = StudyStep(word: card.word, kind: .quiz(kind), cloze: kind == .picture ? cloze : nil)
        if kind != .spell {
            step.choices = QuizRules.choices(for: me, kind: kind, pool: neighbors.words, seed: seed + salt)
        }
        return step
    }
}
