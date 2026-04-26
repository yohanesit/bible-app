//  BibleDatabase.swift
//  BibleApp
//
//  Local on-device Bible text storage.
//
//  Storage layout (under Documents/bible/):
//    • tb     — bundled seed + alkitab.or.id sync (default reading source)
//
//  On first launch the bundle's bible_seed.json (if present) is expanded
//  into bible/tb so lookup is uniform.
//
//  BibleSyncService writes into the local text folder.

import Foundation

// MARK: - Storage types

struct BibleVerse: Codable {
    let v: Int      // verse number
    let t: String   // verse text
    let h: String?  // section heading that precedes this verse (optional)
    let p: Bool?    // true = this verse starts a new paragraph

    init(v: Int, t: String, h: String? = nil, p: Bool? = nil) {
        self.v = v
        self.t = Self.normalizeVerseText(t)
        self.h = h
        self.p = p
    }

    enum CodingKeys: String, CodingKey { case v, t, h, p }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        let raw = try c.decode(String.self, forKey: .t)
        t = Self.normalizeVerseText(raw)
        h = try c.decodeIfPresent(String.self, forKey: .h)
        p = try c.decodeIfPresent(Bool.self, forKey: .p)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(t, forKey: .t)
        try c.encodeIfPresent(h, forKey: .h)
        try c.encodeIfPresent(p, forKey: .p)
    }

    /// PDF / typographic spaces and duplicate gaps → normal word spacing.
    private static func normalizeVerseText(_ s: String) -> String {
        var result = s
        let unicodeSpaces: [(String, String)] = [
            ("\u{00a0}", " "),
            ("\u{2009}", " "),
            ("\u{202f}", " "),
            ("\u{2007}", " "),
        ]
        for (from, to) in unicodeSpaces {
            result = result.replacingOccurrences(of: from, with: to)
        }
        result = result.replacingOccurrences(
            of: #" {2,}"#,
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A single book's data: chapter-number-string → array of verses.
typealias BibleBookData = [String: [BibleVerse]]

// MARK: - Seed format (bundle)

private struct BibleSeed: Decodable {
    let version: String
    /// Increment when bundled `bible_seed.json` content changes so on-disk copies refresh.
    let seedVersion: Int?
    let books: [String: BibleBookData]   // slug → chapters → verses
}

// MARK: - BibleDatabase

final class BibleDatabase {

    static let shared = BibleDatabase()

    private static let bibleSourceKey = "bibleSource"

    private let documentsDirectory: URL
    /// `"source|slug"` → book payload (avoids collisions between trees).
    private var memoryCache: [String: BibleBookData] = [:]

    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory,
                                                      in: .userDomainMask)[0]
        for source in BibleSource.allCases {
            try? FileManager.default.createDirectory(
                at: directory(for: source),
                withIntermediateDirectories: true
            )
        }
        expandSeedIfNeeded()
    }

    // MARK: - Active source (Preferences)

    /// Which tree `passage` / `verses` read from — mirrors `@AppStorage("bibleSource")`.
    var activeSource: BibleSource {
        BibleSource(rawValue: UserDefaults.standard.string(forKey: Self.bibleSourceKey) ?? BibleSource.alkitab.rawValue)
            ?? .alkitab
    }

    func setSource(_ source: BibleSource) {
        UserDefaults.standard.set(source.rawValue, forKey: Self.bibleSourceKey)
        memoryCache.removeAll()
    }

    // MARK: - Query

    /// Returns formatted passage text for the given book/chapter/verseRanges.
    /// Verses are joined inline to keep paragraph flow natural in reading mode.
    /// Returns nil if the book isn't in the DB yet.
    func passage(bookSlug: String,
                 chapter: Int,
                 verseRanges: [ClosedRange<Int>]) -> String? {
        guard let bookData = loadBook(slug: bookSlug, source: activeSource) else { return nil }
        let chapterKey = String(chapter)
        guard let verses = bookData[chapterKey], !verses.isEmpty else { return nil }

        let filtered: [BibleVerse]
        if verseRanges.isEmpty {
            filtered = verses.sorted { $0.v < $1.v }
        } else {
            let wanted = Set(verseRanges.flatMap { Array($0) })
            filtered = verses.filter { wanted.contains($0.v) }
                             .sorted { $0.v < $1.v }
        }

        guard !filtered.isEmpty else { return nil }
        return filtered.map(\.t).joined(separator: " ")
    }

    /// Returns individual BibleVerse objects for a passage — used by the sync engine
    /// to build VerseSegment arrays with per-verse text.
    func passageVerses(bookSlug: String,
                       chapter: Int,
                       verseRanges: [ClosedRange<Int>]) -> [BibleVerse]? {
        guard let bookData = loadBook(slug: bookSlug, source: activeSource) else { return nil }
        let chapterKey = String(chapter)
        guard let verses = bookData[chapterKey], !verses.isEmpty else { return nil }

        let sorted: [BibleVerse]
        if verseRanges.isEmpty {
            sorted = verses.sorted { $0.v < $1.v }
        } else {
            let wanted = Set(verseRanges.flatMap { Array($0) })
            sorted = verses.filter { wanted.contains($0.v) }.sorted { $0.v < $1.v }
        }
        return sorted.isEmpty ? nil : sorted
    }

    /// Returns raw sorted verses for a full chapter — used by BibleChapterProvider.
    func verses(bookSlug: String, chapter: Int) -> [BibleVerse]? {
        guard let bookData = loadBook(slug: bookSlug, source: activeSource) else { return nil }
        let chapterKey = String(chapter)
        guard let verses = bookData[chapterKey], !verses.isEmpty else { return nil }
        return verses.sorted { $0.v < $1.v }
    }

    /// Returns true if at least one book JSON exists for the **active** source.
    var isEmpty: Bool {
        jsonBookCount(in: directory(for: activeSource)) == 0
    }

    /// Returns the number of book JSON files for the **active** source.
    var bookCount: Int {
        jsonBookCount(in: directory(for: activeSource))
    }

    /// Number of `*.json` book files for a given translation tree.
    func bookCount(forSource source: BibleSource) -> Int {
        jsonBookCount(in: directory(for: source))
    }

    // MARK: - Write

    /// Persists a full book into the given source tree and updates the memory cache.
    func writeBook(_ data: BibleBookData, slug: String, toSource source: BibleSource) throws {
        let url = bookURL(slug: slug, source: source)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: url, options: .atomic)
        memoryCache[cacheKey(source: source, slug: slug)] = data
    }

    /// Writes into the default **alkitab** tree (bundled seed expansion).
    func writeBook(_ data: BibleBookData, slug: String) throws {
        try writeBook(data, slug: slug, toSource: .alkitab)
    }

    // MARK: - Private helpers

    private func directory(for source: BibleSource) -> URL {
        documentsDirectory
            .appendingPathComponent("bible", isDirectory: true)
            .appendingPathComponent(source.storageDirName, isDirectory: true)
    }

    private func bookURL(slug: String, source: BibleSource) -> URL {
        directory(for: source).appendingPathComponent("\(slug).json")
    }

    private func cacheKey(source: BibleSource, slug: String) -> String {
        "\(source.rawValue)|\(slug)"
    }

    private func loadBook(slug: String, source: BibleSource) -> BibleBookData? {
        let key = cacheKey(source: source, slug: slug)
        if let cached = memoryCache[key] { return cached }
        let url = bookURL(slug: slug, source: source)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(BibleBookData.self, from: data)
        else { return nil }
        memoryCache[key] = decoded
        return decoded
    }

    private func jsonBookCount(in dir: URL) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return 0 }
        return contents.filter { $0.pathExtension == "json" }.count
    }

    // MARK: - Seed expansion (alkitab / tb only)

    private static let seedBundleRevisionKey = "bibleSeedBundleRevision"

    private func expandSeedIfNeeded() {
        let tbDir = directory(for: .alkitab)
        let sentinel = tbDir.appendingPathComponent(".seeded")

        guard
            let url  = Bundle.main.url(forResource: "bible_seed", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let seed = try? JSONDecoder().decode(BibleSeed.self, from: data)
        else {
            FileManager.default.createFile(atPath: sentinel.path, contents: nil)
            return
        }

        let bundleRevision = seed.seedVersion ?? 1
        let appliedRevision = UserDefaults.standard.integer(forKey: Self.seedBundleRevisionKey)
        let needsRefresh = appliedRevision < bundleRevision

        let seededBookCount = jsonBookCount(in: tbDir)

        if !needsRefresh,
           FileManager.default.fileExists(atPath: sentinel.path),
           seededBookCount >= seed.books.count {
            return
        }

        for (slug, bookData) in seed.books {
            try? writeBook(bookData, slug: slug, toSource: .alkitab)
        }

        UserDefaults.standard.set(bundleRevision, forKey: Self.seedBundleRevisionKey)
        FileManager.default.createFile(atPath: sentinel.path, contents: nil)
    }
}
