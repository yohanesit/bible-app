//  BibleCatalog.swift
//  BibleApp
//
//  Single source of truth for all 73 Catholic Bible books:
//  Indonesian name, database slug, chapter count, and canonical section.
//  Used by LeftPaneView, RightPaneView, BibleChapterProvider, and BibleSyncService.

import Foundation

// MARK: - BibleSection

enum BibleSection: String, CaseIterable {
    case oldTestament      = "Perjanjian Lama"
    case deuterocanonical  = "Deuterokanonika"
    case newTestament      = "Perjanjian Baru"
}

// MARK: - BibleBookEntry

struct BibleBookEntry: Identifiable {
    let slug: String
    let name: String           // Indonesian display name
    let section: BibleSection
    let chapterCount: Int

    var id: String { slug }
}

// MARK: - BibleCatalog

enum BibleCatalog {

    // MARK: - All 73 Catholic books

    static let books: [BibleBookEntry] = [

        // ── Old Testament (39) ────────────────────────────────────────────
        .init(slug: "kej",  name: "Kejadian",         section: .oldTestament, chapterCount: 50),
        .init(slug: "kel",  name: "Keluaran",          section: .oldTestament, chapterCount: 40),
        .init(slug: "ima",  name: "Imamat",            section: .oldTestament, chapterCount: 27),
        .init(slug: "bil",  name: "Bilangan",          section: .oldTestament, chapterCount: 36),
        .init(slug: "ul",   name: "Ulangan",           section: .oldTestament, chapterCount: 34),
        .init(slug: "yos",  name: "Yosua",             section: .oldTestament, chapterCount: 24),
        .init(slug: "hak",  name: "Hakim-Hakim",       section: .oldTestament, chapterCount: 21),
        .init(slug: "rut",  name: "Rut",               section: .oldTestament, chapterCount: 4),
        .init(slug: "1sam", name: "1 Samuel",          section: .oldTestament, chapterCount: 31),
        .init(slug: "2sam", name: "2 Samuel",          section: .oldTestament, chapterCount: 24),
        .init(slug: "1raj", name: "1 Raja-Raja",       section: .oldTestament, chapterCount: 22),
        .init(slug: "2raj", name: "2 Raja-Raja",       section: .oldTestament, chapterCount: 25),
        .init(slug: "1taw", name: "1 Tawarikh",        section: .oldTestament, chapterCount: 29),
        .init(slug: "2taw", name: "2 Tawarikh",        section: .oldTestament, chapterCount: 36),
        .init(slug: "ezr",  name: "Ezra",              section: .oldTestament, chapterCount: 10),
        .init(slug: "neh",  name: "Nehemia",           section: .oldTestament, chapterCount: 13),
        .init(slug: "est",  name: "Ester",             section: .oldTestament, chapterCount: 10),
        .init(slug: "ayb",  name: "Ayub",              section: .oldTestament, chapterCount: 42),
        .init(slug: "mzm",  name: "Mazmur",            section: .oldTestament, chapterCount: 150),
        .init(slug: "ams",  name: "Amsal",             section: .oldTestament, chapterCount: 31),
        .init(slug: "pkh",  name: "Pengkhotbah",       section: .oldTestament, chapterCount: 12),
        .init(slug: "kid",  name: "Kidung Agung",      section: .oldTestament, chapterCount: 8),
        .init(slug: "yes",  name: "Yesaya",            section: .oldTestament, chapterCount: 66),
        .init(slug: "yer",  name: "Yeremia",           section: .oldTestament, chapterCount: 52),
        .init(slug: "rat",  name: "Ratapan",           section: .oldTestament, chapterCount: 5),
        .init(slug: "yeh",  name: "Yehezkiel",         section: .oldTestament, chapterCount: 48),
        .init(slug: "dan",  name: "Daniel",            section: .oldTestament, chapterCount: 12),
        .init(slug: "hos",  name: "Hosea",             section: .oldTestament, chapterCount: 14),
        .init(slug: "yol",  name: "Yoel",              section: .oldTestament, chapterCount: 3),
        .init(slug: "amo",  name: "Amos",              section: .oldTestament, chapterCount: 9),
        .init(slug: "oba",  name: "Obaja",             section: .oldTestament, chapterCount: 1),
        .init(slug: "yun",  name: "Yunus",             section: .oldTestament, chapterCount: 4),
        .init(slug: "mik",  name: "Mikha",             section: .oldTestament, chapterCount: 7),
        .init(slug: "nah",  name: "Nahum",             section: .oldTestament, chapterCount: 3),
        .init(slug: "hab",  name: "Habakuk",           section: .oldTestament, chapterCount: 3),
        .init(slug: "zef",  name: "Zefanya",           section: .oldTestament, chapterCount: 3),
        .init(slug: "hag",  name: "Hagai",             section: .oldTestament, chapterCount: 2),
        .init(slug: "zak",  name: "Zakharia",          section: .oldTestament, chapterCount: 14),
        .init(slug: "mal",  name: "Maleakhi",          section: .oldTestament, chapterCount: 4),

        // ── Deuterocanonical (7) ──────────────────────────────────────────
        .init(slug: "tob",  name: "Tobit",             section: .deuterocanonical, chapterCount: 14),
        .init(slug: "ydt",  name: "Yudit",             section: .deuterocanonical, chapterCount: 16),
        .init(slug: "1mak", name: "1 Makabe",          section: .deuterocanonical, chapterCount: 16),
        .init(slug: "2mak", name: "2 Makabe",          section: .deuterocanonical, chapterCount: 15),
        .init(slug: "keb",  name: "Kebijaksanaan",     section: .deuterocanonical, chapterCount: 19),
        .init(slug: "sir",  name: "Sirakh",            section: .deuterocanonical, chapterCount: 51),
        .init(slug: "bar",  name: "Barukh",            section: .deuterocanonical, chapterCount: 6),

        // ── New Testament (27) ────────────────────────────────────────────
        .init(slug: "mat",  name: "Matius",            section: .newTestament, chapterCount: 28),
        .init(slug: "mrk",  name: "Markus",            section: .newTestament, chapterCount: 16),
        .init(slug: "luk",  name: "Lukas",             section: .newTestament, chapterCount: 24),
        .init(slug: "yoh",  name: "Yohanes",           section: .newTestament, chapterCount: 21),
        .init(slug: "kis",  name: "Kisah Para Rasul",  section: .newTestament, chapterCount: 28),
        .init(slug: "rom",  name: "Roma",              section: .newTestament, chapterCount: 16),
        .init(slug: "1kor", name: "1 Korintus",        section: .newTestament, chapterCount: 16),
        .init(slug: "2kor", name: "2 Korintus",        section: .newTestament, chapterCount: 13),
        .init(slug: "gal",  name: "Galatia",           section: .newTestament, chapterCount: 6),
        .init(slug: "ef",   name: "Efesus",            section: .newTestament, chapterCount: 6),
        .init(slug: "flp",  name: "Filipi",            section: .newTestament, chapterCount: 4),
        .init(slug: "kol",  name: "Kolose",            section: .newTestament, chapterCount: 4),
        .init(slug: "1tes", name: "1 Tesalonika",      section: .newTestament, chapterCount: 5),
        .init(slug: "2tes", name: "2 Tesalonika",      section: .newTestament, chapterCount: 3),
        .init(slug: "1tim", name: "1 Timotius",        section: .newTestament, chapterCount: 6),
        .init(slug: "2tim", name: "2 Timotius",        section: .newTestament, chapterCount: 4),
        .init(slug: "tit",  name: "Titus",             section: .newTestament, chapterCount: 3),
        .init(slug: "flm",  name: "Filemon",           section: .newTestament, chapterCount: 1),
        .init(slug: "ibr",  name: "Ibrani",            section: .newTestament, chapterCount: 13),
        .init(slug: "yak",  name: "Yakobus",           section: .newTestament, chapterCount: 5),
        .init(slug: "1ptr", name: "1 Petrus",          section: .newTestament, chapterCount: 5),
        .init(slug: "2ptr", name: "2 Petrus",          section: .newTestament, chapterCount: 3),
        .init(slug: "1yoh", name: "1 Yohanes",         section: .newTestament, chapterCount: 5),
        .init(slug: "2yoh", name: "2 Yohanes",         section: .newTestament, chapterCount: 1),
        .init(slug: "3yoh", name: "3 Yohanes",         section: .newTestament, chapterCount: 1),
        .init(slug: "yud",  name: "Yudas",             section: .newTestament, chapterCount: 1),
        .init(slug: "why",  name: "Wahyu",             section: .newTestament, chapterCount: 22),
    ]

    // MARK: - Lookups

    static func entry(forSlug slug: String) -> BibleBookEntry? {
        books.first { $0.slug == slug }
    }

    static func entry(forName name: String) -> BibleBookEntry? {
        books.first { $0.name == name }
    }

    /// Books grouped by section, in canonical order.
    static var bySection: [(section: BibleSection, books: [BibleBookEntry])] {
        BibleSection.allCases.compactMap { section in
            let filtered = books.filter { $0.section == section }
            guard !filtered.isEmpty else { return nil }
            return (section, filtered)
        }
    }
}
