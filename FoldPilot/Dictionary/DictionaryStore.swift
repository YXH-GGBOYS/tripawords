import Foundation
import SQLite3

/// Read-only access to the bundled `foldpilot.sqlite` (built by pipeline/scripts).
@MainActor
final class DictionaryStore {
    enum OpenError: Error { case missing, sqlite(String) }

    private var db: OpaquePointer?
    private let decoder = JSONDecoder()

    init(url: URL? = Bundle.main.url(forResource: "foldpilot", withExtension: "sqlite")) throws {
        guard let url else { throw OpenError.missing }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw OpenError.sqlite(message)
        }
    }

    isolated deinit {
        sqlite3_close(db)
    }

    func brief(_ word: String) -> BriefEntry? {
        query("SELECT word, phonetic, translation, rank FROM entry WHERE word = ?", word) { row in
            BriefEntry(
                word: row.text(0) ?? word,
                phonetic: row.text(1).flatMap { $0.isEmpty ? nil : $0 },
                lines: (row.text(2) ?? "").split(separator: "\n").map(String.init),
                rank: row.int(3)
            )
        }.first
    }

    /// Lemmas that `form` is an inflection of, e.g. "fled" -> ["flee"].
    func lemmas(of form: String) -> [String] {
        query("SELECT lemma FROM form WHERE form = ?", form) { $0.text(0) }.compactMap { $0 }
    }

    func atlas(_ word: String) -> AtlasEntry? {
        query("""
            SELECT word, uk, senses, examples, collocations, family, synonyms, antonyms,
                   tip, note, cefr, image
            FROM atlas WHERE word = ?
            """, word) { row in
            AtlasEntry(
                word: row.text(0) ?? word,
                ipa: row.text(1),
                senses: decode(row.text(2)) ?? [],
                examples: decode(row.text(3)) ?? [],
                collocations: decode(row.text(4)) ?? [],
                family: decode(row.text(5)) ?? [],
                synonyms: decode(row.text(6)) ?? [],
                antonyms: decode(row.text(7)) ?? [],
                tip: row.text(8),
                note: row.text(9),
                cefr: row.text(10),
                image: row.text(11)
            )
        }.first
    }

    /// word-atlas words near `route` on its learning path, for quiz distractors.
    func atlasNeighbors(of word: String, span: Int = 400) -> (route: Int, words: [AtlasStub])? {
        guard let route = query("SELECT route FROM atlas WHERE word = ?", word, map: { $0.int(0) }).first
        else { return nil }
        let words = query("""
            SELECT word, senses, cefr, image FROM atlas WHERE route BETWEEN ? AND ? ORDER BY route
            """, [.int(route - span), .int(route + span)]) { row in
            let senses: [AtlasEntry.Sense] = decode(row.text(1)) ?? []
            return AtlasStub(word: row.text(0) ?? "", pos: senses.first?.pos ?? "",
                             zh: senses.first?.zh ?? "", cefr: row.text(2) ?? "", hasImage: row.text(3) != nil)
        }
        return (route, words)
    }

    private func decode<T: Decodable>(_ json: String?) -> T? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private struct Row {
        let stmt: OpaquePointer
        func text(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
    }

    private enum Arg { case text(String), int(Int) }

    private func query<T>(_ sql: String, _ arg: String, map: (Row) -> T) -> [T] {
        query(sql, [.text(arg)], map: map)
    }

    private func query<T>(_ sql: String, _ args: [Arg], map: (Row) -> T) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            switch arg {
            case .text(let v): sqlite3_bind_text(stmt, Int32(i + 1), v, -1, transient)
            case .int(let v): sqlite3_bind_int64(stmt, Int32(i + 1), Int64(v))
            }
        }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(map(Row(stmt: stmt)))
        }
        return out
    }
}
