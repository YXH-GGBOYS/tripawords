import Foundation
import SwiftData
import Testing
@testable import FoldPilot

@MainActor
struct ReviewSchedulerTests {
    let container = try! ModelContainer(
        for: StudyCard.self, ReviewEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private func addCards(_ n: Int, at now: Date) {
        for i in 0..<n {
            container.mainContext.insert(StudyCard(
                word: "w\(i)", meaning: "m", rootFamily: "", source: "", imageName: nil, context: nil,
                now: now.addingTimeInterval(Double(i))
            ))
        }
        try! container.mainContext.save()
    }

    @Test func newCardLimitPerDay() {
        let now = Date()
        addCards(12, at: now.addingTimeInterval(-60))
        let scheduler = ReviewScheduler(context: container.mainContext, newPerDay: 10, reviewsPerDay: 100)
        #expect(scheduler.todayCount(now: now) == 10)

        var introduced = 0
        while let card = scheduler.next(now: now), card.isNew {
            scheduler.answer(card, with: .knew, now: now)
            introduced += 1
            if introduced > 20 { break }
        }
        #expect(introduced == 10)
    }

    @Test func knownCardMovesOutOfToday() throws {
        let now = Date()
        addCards(1, at: now.addingTimeInterval(-60))
        let scheduler = ReviewScheduler(context: container.mainContext, newPerDay: 10, reviewsPerDay: 100)
        let card = try #require(scheduler.next(now: now))
        scheduler.answer(card, with: .knew, now: now)
        scheduler.answer(card, with: .knew, now: now.addingTimeInterval(15 * 60))
        #expect(!card.isNew)
        #expect(card.due > now.addingTimeInterval(12 * 3600))
    }

    @Test func forgottenCardComesBackSoon() throws {
        let now = Date()
        addCards(1, at: now.addingTimeInterval(-60))
        let scheduler = ReviewScheduler(context: container.mainContext, newPerDay: 10, reviewsPerDay: 100)
        let card = try #require(scheduler.next(now: now))
        scheduler.answer(card, with: .forgot, now: now)
        #expect(card.due < now.addingTimeInterval(15 * 60))
        #expect(scheduler.next(now: now.addingTimeInterval(15 * 60))?.word == card.word)
    }
}
