import Foundation
import FSRS
import SwiftData

/// A flashcard (plan §4.3). Front: `word` only. Back: meaning, etymology in small grey type,
/// illustration. `schedule` holds the FSRS state; `due` is copied out of it so it can be queried.
@Model
final class StudyCard {
    @Attribute(.unique) var word: String
    var meaning: String
    /// Empty until the deep level exists (decision 18).
    var etymology: String
    var rootFamily: String
    var source: String
    /// File name in the bundled word-atlas `thumb` folder.
    var imageName: String?
    /// The sentence the word was copied in, when there was one.
    var context: String?
    var tags: [String]
    var createdAt: Date

    var due: Date
    var isNew: Bool
    /// First time the card was shown in a review, for the daily new-card limit.
    var introducedAt: Date?
    var schedule: Data

    init(word: String, meaning: String, rootFamily: String, source: String,
         imageName: String?, context: String?, now: Date = .now) {
        self.word = word
        self.meaning = meaning
        self.etymology = ""
        self.rootFamily = rootFamily
        self.source = source
        self.imageName = imageName
        self.context = context
        self.tags = []
        self.createdAt = now
        let fresh = Card(due: now)
        self.due = fresh.due
        self.isNew = true
        self.schedule = (try? JSONEncoder().encode(fresh)) ?? Data()
    }

    var fsrsCard: Card {
        get { (try? JSONDecoder().decode(Card.self, from: schedule)) ?? Card(due: createdAt) }
        set {
            schedule = (try? JSONEncoder().encode(newValue)) ?? schedule
            due = newValue.due
            isNew = newValue.state == .new
        }
    }
}

/// One answer in a review session; kept for daily limits and a later FSRS parameter fit.
@Model
final class ReviewEntry {
    var word: String
    var rating: Int
    var wasNew: Bool
    var reviewedAt: Date

    init(word: String, rating: Int, wasNew: Bool, reviewedAt: Date = .now) {
        self.word = word
        self.rating = rating
        self.wasNew = wasNew
        self.reviewedAt = reviewedAt
    }
}
