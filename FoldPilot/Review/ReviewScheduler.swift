import Foundation
import FSRS
import SwiftData

/// The three self-rated answers on a flip card (spec §4.4) mapped onto FSRS ratings.
enum ReviewAnswer: CaseIterable {
    case forgot, fuzzy, knew

    var label: String {
        switch self {
        case .forgot: "不认识"
        case .fuzzy: "模糊"
        case .knew: "认识"
        }
    }

    var rating: Rating {
        switch self {
        case .forgot: .again
        case .fuzzy: .hard
        case .knew: .good
        }
    }
}

/// Builds today's queue under the daily limits and applies answers with FSRS-6.
@MainActor
struct ReviewScheduler {
    static let defaultNewPerDay = 10
    static let defaultReviewsPerDay = 100
    /// A study day starts at 4:00 local time (from Wordbook), so late-night reviews count
    /// towards the day the learner is still in.
    nonisolated static let dayStartHour = 4

    let context: ModelContext
    var newPerDay = defaultNewPerDay
    var reviewsPerDay = defaultReviewsPerDay
    private let fsrs = FSRS(parameters: .init(w: FSRSDefaults.defaultWv6))

    init(context: ModelContext, newPerDay: Int, reviewsPerDay: Int) {
        self.context = context
        self.newPerDay = newPerDay
        self.reviewsPerDay = reviewsPerDay
    }

    nonisolated static func dayStart(for now: Date, calendar: Calendar = .current) -> Date {
        let shifted = now.addingTimeInterval(-Double(dayStartHour) * 3600)
        let midnight = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: dayStartHour, to: midnight) ?? midnight
    }

    /// Next card to show, or nil when today's work is done.
    func next(now: Date = .now) -> StudyCard? {
        dueToday(now: now, limit: 1).first ?? newToday(now: now, limit: 1).first
    }

    /// Count shown on the home screen: due reviews plus the new cards still allowed today.
    func todayCount(now: Date = .now) -> Int {
        dueToday(now: now, limit: nil).count + newToday(now: now, limit: nil).count
    }

    /// Due reviews still allowed today, earliest first.
    func dueToday(now: Date = .now, limit: Int?) -> [StudyCard] {
        let left = reviewsLeft(now: now)
        guard left > 0 else { return [] }
        return dueCards(now: now, limit: min(limit ?? left, left))
    }

    /// New cards still allowed today, oldest first.
    func newToday(now: Date = .now, limit: Int?) -> [StudyCard] {
        let left = newLeft(now: now)
        guard left > 0 else { return [] }
        return newCards(limit: min(limit ?? left, left))
    }

    func answer(_ card: StudyCard, with answer: ReviewAnswer, now: Date = .now) {
        apply(answer.rating, to: card, now: now)
    }

    func apply(_ rating: Rating, to card: StudyCard, now: Date = .now) {
        let wasNew = card.isNew
        if wasNew, card.introducedAt == nil { card.introducedAt = now }
        if let result = try? fsrs.next(card: card.fsrsCard, now: now, grade: rating) {
            card.fsrsCard = result.card
        }
        context.insert(ReviewEntry(word: card.word, rating: rating.rawValue, wasNew: wasNew, reviewedAt: now))
        try? context.save()
    }

    /// When the card would come back for each answer, for the labels on the answer buttons.
    func preview(_ card: StudyCard, now: Date = .now) -> [ReviewAnswer: TimeInterval] {
        var out: [ReviewAnswer: TimeInterval] = [:]
        for answer in ReviewAnswer.allCases {
            if let result = try? fsrs.next(card: card.fsrsCard, now: now, grade: answer.rating) {
                out[answer] = result.card.due.timeIntervalSince(now)
            }
        }
        return out
    }

    /// "10 分钟" / "1 天" / "3 个月".
    nonisolated static func describe(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = Int((interval / 3600).rounded())
        if hours < 24 { return "\(hours) 小时" }
        let days = Int((interval / 86400).rounded())
        if days < 31 { return "\(days) 天" }
        if days < 365 { return "\(days / 30) 个月" }
        return String(format: "%.1f 年", Double(days) / 365)
    }

    private func dueCards(now: Date, limit: Int?) -> [StudyCard] {
        var descriptor = FetchDescriptor<StudyCard>(
            predicate: #Predicate { !$0.isNew && $0.due <= now },
            sortBy: [SortDescriptor(\.due)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    private func newCards(limit: Int?) -> [StudyCard] {
        var descriptor = FetchDescriptor<StudyCard>(
            predicate: #Predicate { $0.isNew },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    private func newLeft(now: Date) -> Int {
        let start = Self.dayStart(for: now)
        let introduced = (try? context.fetchCount(FetchDescriptor<StudyCard>(
            predicate: #Predicate { $0.introducedAt != nil && $0.introducedAt! >= start }
        ))) ?? 0
        return max(0, newPerDay - introduced)
    }

    private func reviewsLeft(now: Date) -> Int {
        let start = Self.dayStart(for: now)
        let done = (try? context.fetchCount(FetchDescriptor<ReviewEntry>(
            predicate: #Predicate { !$0.wasNew && $0.reviewedAt >= start }
        ))) ?? 0
        return max(0, reviewsPerDay - done)
    }
}
