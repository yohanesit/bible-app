//  BibleSyncService.swift
//  BibleApp
//
//  Admin-triggered service that fetches the full TB Bible text from
//  bible-api.alkitab.or.id and writes it into BibleDatabase.
//
//  Requires an API key from bible-api.alkitab.or.id (register at the site).
//  The key is stored in UserDefaults under "alkitabApiKey".
//
//  Endpoint per chapter:
//    GET https://bible-api.alkitab.or.id/bible/tb/{book_slug}/{chapter}
//    Headers: Authorization: Bearer {API_KEY}

import Foundation
import Observation

// MARK: - API response model

private struct AlkitabChapterResponse: Decodable {
    let book: String?
    let chapter: Int?
    let verses: [AlkitabVerse]

    enum CodingKeys: String, CodingKey {
        case book, chapter, verses
        case data    // some versions nest verses under "data"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        book    = try? c.decode(String.self, forKey: .book)
        chapter = try? c.decode(Int.self,    forKey: .chapter)
        verses  = (try? c.decode([AlkitabVerse].self, forKey: .verses))
               ?? (try? c.decode([AlkitabVerse].self, forKey: .data))
               ?? []
    }
}

private struct AlkitabVerse: Decodable {
    let verse: Int
    let text: String
    let heading: String?

    enum CodingKeys: String, CodingKey {
        case verse, text
        case v, t          // compact keys
        case number, content
        case heading, h, title
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verse = (try? c.decode(Int.self, forKey: .verse))
             ?? (try? c.decode(Int.self, forKey: .v))
             ?? (try? c.decode(Int.self, forKey: .number))
             ?? 0
        text  = (try? c.decode(String.self, forKey: .text))
             ?? (try? c.decode(String.self, forKey: .t))
             ?? (try? c.decode(String.self, forKey: .content))
             ?? ""
        let rawHeading = (try? c.decode(String.self, forKey: .heading))
            ?? (try? c.decode(String.self, forKey: .h))
            ?? (try? c.decode(String.self, forKey: .title))
        let trimmed = rawHeading?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        heading = trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Book manifest (slug → chapter count for TB)
// Chapter counts for the full TB canon so we know how many
// chapters to fetch per book.

private let tbChapterCounts: [(slug: String, chapters: Int)] = [
    ("kej", 50), ("kel", 40), ("ima", 27), ("bil", 36), ("ul",  34),
    ("yos", 24), ("hak", 21), ("rut",  4), ("1sam",31), ("2sam",24),
    ("1raj",22), ("2raj",25), ("1taw",29), ("2taw",36), ("ezr", 10),
    ("neh", 13), ("est",  10), ("ayb", 42), ("mzm",150), ("ams", 31),
    ("pkh",  12), ("kid",   8), ("yes", 66), ("yer", 52), ("rat",  5),
    ("yeh", 48), ("dan",  12), ("hos", 14), ("yol",  3), ("amo",  9),
    ("oba",  1), ("yun",   4), ("mik",  7), ("nah",  3), ("hab",  3),
    ("zef",  3), ("hag",   2), ("zak", 14), ("mal",  4),
    // Deuterocanonical — skipped in TB sync; sourced from bible_seed separately
    // New Testament
    ("mat", 28), ("mrk", 16), ("luk", 24), ("yoh", 21),
    ("kis", 28), ("rom", 16), ("1kor",16), ("2kor",13), ("gal",  6),
    ("ef",   6), ("flp",  4), ("kol",  4), ("1tes", 5), ("2tes", 3),
    ("1tim", 6), ("2tim", 4), ("tit",  3), ("flm",  1), ("ibr", 13),
    ("yak",  5), ("1ptr", 5), ("2ptr", 3), ("1yoh", 5), ("2yoh", 1),
    ("3yoh", 1), ("yud",  1), ("why", 22)
]

// MARK: - BibleSyncService

@Observable
final class BibleSyncService {

    // MARK: Published state

    var isSyncing = false
    var progress: Double = 0          // 0.0 – 1.0
    var currentBook: String = ""
    var error: String? = nil

    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastBibleSync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBibleSync") }
    }

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "alkitabApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "alkitabApiKey") }
    }

    var hasApiKey: Bool { !apiKey.isEmpty }

    // MARK: Private

    private let baseURL = "https://bible-api.alkitab.or.id/bible/tb"
    private let db = BibleDatabase.shared
    private var syncTask: Task<Void, Never>?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    func startSync() {
        guard !isSyncing else { return }
        syncTask = Task { await runSync() }
    }

    func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
        currentBook = ""
        progress = 0
    }

    // MARK: - Sync logic

    @MainActor
    private func runSync() async {
        guard hasApiKey else {
            error = "Please enter your Alkitab API key before syncing."
            return
        }

        isSyncing = true
        error = nil
        progress = 0

        let totalChapters = tbChapterCounts.reduce(0) { $0 + $1.chapters }
        var completedChapters = 0

        for (slug, chapterCount) in tbChapterCounts {
            guard !Task.isCancelled else { break }

            currentBook = slug
            var bookData: BibleBookData = [:]

            for chapter in 1...chapterCount {
                guard !Task.isCancelled else { break }

                if let chapterData = try? await fetchChapter(slug: slug, chapter: chapter) {
                    bookData[String(chapter)] = chapterData
                }

                completedChapters += 1
                progress = Double(completedChapters) / Double(totalChapters)
            }

            if !bookData.isEmpty {
                try? db.writeBook(bookData, slug: slug, toSource: BibleSource.alkitab)
            }
        }

        if !Task.isCancelled {
            lastSyncDate = Date()
        }

        isSyncing = false
        currentBook = ""
        progress = Task.isCancelled ? 0 : 1.0
    }

    private func fetchChapter(slug: String, chapter: Int) async throws -> [BibleVerse] {
        let url = URL(string: "\(baseURL)/\(slug)/\(chapter)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await session.data(for: request)
        let response  = try JSONDecoder().decode(AlkitabChapterResponse.self, from: data)

        return response.verses.map { BibleVerse(v: $0.verse, t: $0.text, h: $0.heading) }
    }
}

