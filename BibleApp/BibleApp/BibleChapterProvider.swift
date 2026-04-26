//  BibleChapterProvider.swift
//  BibleApp
//
//  Loads a single Bible chapter from BibleDatabase and exposes it to the UI.
//  BibleDatabase reads are synchronous (local file), so no async is needed.
//  Injected into the SwiftUI environment alongside DailyReadingProvider.

import Foundation
import Observation

// MARK: - ChapterLoadState

enum ChapterLoadState {
    case idle
    case loaded(bookName: String, chapter: Int, verses: [BibleVerse])
    case empty(bookName: String, chapter: Int)   // book not synced yet

    var verses: [BibleVerse]? {
        if case .loaded(_, _, let v) = self { return v }
        return nil
    }

    var bookName: String? {
        switch self {
        case .loaded(let n, _, _), .empty(let n, _): return n
        case .idle: return nil
        }
    }

    var chapter: Int? {
        switch self {
        case .loaded(_, let c, _), .empty(_, let c): return c
        case .idle: return nil
        }
    }
}

// MARK: - BibleChapterProvider

@Observable
final class BibleChapterProvider {

    var state: ChapterLoadState = .idle

    private let db = BibleDatabase.shared

    // MARK: - Public

    func load(slug: String, chapter: Int) {
        guard let entry = BibleCatalog.entry(forSlug: slug) else { return }
        let bookName = entry.name

        if let verses = db.verses(bookSlug: slug, chapter: chapter), !verses.isEmpty {
            state = .loaded(bookName: bookName, chapter: chapter, verses: verses)
            print("📚 [BibleDB] Loaded \(bookName) \(chapter) — \(verses.count) verse(s)")
        } else {
            state = .empty(bookName: bookName, chapter: chapter)
            print("⚠️ [BibleDB] \(bookName) \(chapter) not in database — sync needed")
        }
    }

    func load(bookName: String, chapter: Int) {
        guard let entry = BibleCatalog.entry(forName: bookName) else {
            print("⚠️ [BibleDB] Unknown book: \(bookName)")
            return
        }
        load(slug: entry.slug, chapter: chapter)
    }
}
