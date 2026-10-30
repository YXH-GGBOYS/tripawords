import Foundation
import SwiftData

/// One row of lookup history. Only the headword and the copied text are kept, on device.
@Model
final class LookupRecord {
    @Attribute(.unique) var headword: String
    var query: String
    var lookedUpAt: Date

    init(headword: String, query: String, lookedUpAt: Date = .now) {
        self.headword = headword
        self.query = query
        self.lookedUpAt = lookedUpAt
    }
}
