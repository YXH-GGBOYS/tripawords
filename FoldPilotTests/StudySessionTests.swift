import Foundation
import FSRS
import SwiftData
import Testing
@testable import FoldPilot

struct QuizRulesTests {
    @Test func grading() {
        #expect(QuizRules.grade(kind: .meaning, correct: false, elapsed: .seconds(1), hinted: false) == .again)
        #expect(QuizRules.grade(kind: .meaning, correct: true, elapsed: .seconds(3), hinted: false) == .good)
        #expect(QuizRules.grade(kind: .meaning, correct: true, elapsed: .seconds(12), hinted: false) == .hard)
        #expect(QuizRules.grade(kind: .spell, correct: true, elapsed: .seconds(4), hinted: false) == .easy)
        #expect(QuizRules.grade(kind: .spell, correct: true, elapsed: .seconds(4), hinted: true) == .hard)
    }

    @Test func clozeBlanksInflections() {
        #expect(QuizRules.cloze("The official faced treason charges.", word: "treason") == "The official faced _____ charges.")
        #expect(QuizRules.cloze("Spring flowers herald the new season.", word: "herald") == "Spring flowers _____ the new season.")
        #expect(QuizRules.cloze("She abandoned the plan.", word: "abandon") == "She _____ the plan.")
        #expect(QuizRules.cloze("Nothing to see here.", word: "treason") == nil)
    }

    @Test func dayStartsAtFourInTheMorning() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let lateNight = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 1, minute: 30))!
        let start = ReviewScheduler.dayStart(for: lateNight, calendar: cal)
        #expect(start == cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 4))!)
    }

    @Test func intervalLabels() {
        #expect(ReviewScheduler.describe(600) == "10 分钟")
        #expect(ReviewScheduler.describe(86400 * 4) == "4 天")
        #expect(ReviewScheduler.describe(86400 * 90) == "3 个月")
    }
}

@MainActor
struct StudySessionTests {
    let container = try! ModelContainer(
        for: StudyCard.self, ReviewEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let store = try! DictionaryStore()

    private func add(_ words: [String], at now: Date) {
        for (i, w) in words.enumerated() {
            let atlas = store.atlas(w)
            container.mainContext.insert(StudyCard(
                word: w, meaning: atlas?.senses.first?.zh ?? "m", rootFamily: "", source: "",
                imageName: atlas?.image, context: nil, now: now.addingTimeInterval(Double(i))
            ))
        }
        try! container.mainContext.save()
    }

    @Test func newWordsAreIntroducedThenQuizzed() throws {
        let now = Date()
        add(["treason", "herald", "abandon", "oath", "realm", "fealty"], at: now.addingTimeInterval(-60))
        let scheduler = ReviewScheduler(context: container.mainContext, newPerDay: 10, reviewsPerDay: 100)
        let session = StudySession(scheduler: scheduler, store: store, now: now)

        let intros = session.steps.filter { $0.kind == .intro }.map(\.word)
        let quizzes = session.steps.compactMap { step -> StudyStep? in
            if case .quiz = step.kind { return step } else { return nil }
        }
        let flips = session.steps.filter { $0.kind == .flip }.map(\.word)
        // fealty is not a word-atlas word: flip card, no intro, no quiz.
        #expect(flips == ["fealty"])
        #expect(Set(intros) == ["treason", "herald", "abandon", "oath", "realm"])
        #expect(quizzes.count == 5)
        for quiz in quizzes where quiz.kind != .quiz(.spell) {
            #expect(quiz.choices.count == 4)
            #expect(quiz.choices.contains { $0.word == quiz.word })
            #expect(Set(quiz.choices.map(\.word)).count == 4)
        }
    }

    @Test func onlyFirstAnswerCountsAndWrongAnswersComeBack() throws {
        let now = Date()
        add(["treason"], at: now.addingTimeInterval(-60))
        let scheduler = ReviewScheduler(context: container.mainContext, newPerDay: 10, reviewsPerDay: 100)
        let session = StudySession(scheduler: scheduler, store: store, now: now)
        #expect(session.current?.kind == .intro)
        session.continueFromIntro()
        let before = session.steps.count
        session.answerQuiz(correct: false, elapsed: .seconds(2), hinted: false)
        #expect(session.steps.count == before + 1)
        #expect(session.current?.isRetry == true)
        session.answerQuiz(correct: true, elapsed: .seconds(2), hinted: false)
        let entries = try container.mainContext.fetch(FetchDescriptor<ReviewEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.rating == Rating.again.rawValue)
    }
}
