//  LagumisaSlugDeriver.swift
//  BibleApp
//
//  Maps a MassDay's (celebrationName, date) pair to a lagumisa.web.id slug,
//  which is then used to look up the bundled sung refrain text.
//
//  Coverage:
//   - All Sunday Masses (A/B/C cycles): derived programmatically
//   - Major solemnities and feasts: static lookup table
//   - Weekday ferias: returns nil (no refrain shown)

import Foundation

enum LagumisaSlugDeriver {

    // MARK: - Public API

    /// Returns a lagumisa slug for the given celebration name and date,
    /// or nil if no mapping is available (e.g. ordinary weekday).
    static func slug(for celebrationName: String, on date: Date) -> String? {
        let cycle = liturgicalCycle(for: date)   // "a", "b", or "c"
        let lower = celebrationName.lowercased()

        // 1. Try Sunday derivation (handles "Minggu Adven I", "Minggu Biasa 5", etc.)
        if let sundaySlug = deriveSundaySlug(from: lower, cycle: cycle) {
            return sundaySlug
        }

        // 2. Try the static feast/solemnity table
        return feastSlug(from: lower, cycle: cycle)
    }

    // MARK: - Liturgical Cycle

    /// Returns "a", "b", or "c" for the liturgical cycle that contains the given date.
    ///
    /// Cycle determination:
    ///   liturgical year = civil year of that cycle's Advent start
    ///   Advent starts on the Sunday closest to Nov 30 (≈ Nov 27 – Dec 3)
    ///   Year A when liturgicalYear % 3 == 2  (e.g. 2025, 2028, 2031…)
    ///   Year B when liturgicalYear % 3 == 0  (e.g. 2026, 2029, 2032…)
    ///   Year C when liturgicalYear % 3 == 1  (e.g. 2027, 2030, 2033…)
    ///
    ///   Verified: 2024-25 → C ✓, 2025-26 → A ✓, 2026-27 → B ✓, 2027-28 → C ✓
    static func liturgicalCycle(for date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day
        else { return "a" }

        // If date is on or after Dec 1, it belongs to the new liturgical year (year+1)
        // If date is in Nov 27–30, it might be Advent already — use Nov 27 as cutoff
        let liturgicalYear: Int
        if month == 12 || (month == 11 && day >= 27) {
            liturgicalYear = year + 1
        } else {
            liturgicalYear = year
        }

        let cycles = ["b", "c", "a"]   // index 0,1,2 for year%3 == 0,1,2
        return cycles[liturgicalYear % 3]
    }

    // MARK: - Sunday Slug Derivation

    private static func deriveSundaySlug(from lower: String, cycle: String) -> String? {
        // Must contain "minggu" (Sunday)
        guard lower.contains("minggu") else { return nil }

        // --- Season detection ---
        let seasonSlug: String
        if lower.contains("adven") {
            seasonSlug = "adven"
        } else if lower.contains("prapaskah") {
            seasonSlug = "prapaskah"
        } else if lower.contains("paskah") && !lower.contains("hr paskah") && !lower.contains("hari raya paskah") {
            seasonSlug = "paskah"
        } else if lower.contains("biasa") {
            seasonSlug = "biasa"
        } else if lower.contains("natal") {
            seasonSlug = "natal"
        } else if lower.contains("kristus raja") || lower.contains("biasa-34") {
            // Solemnity of Christ the King = Minggu Biasa 34
            return "\(cycle)-minggu-biasa-34-hr-kristus-raja"
        } else {
            return nil
        }

        // --- Week number detection ---
        // Supports Arabic (1–34) and Roman numerals (I–XXXIV)
        guard let week = extractWeekNumber(from: lower) else { return nil }

        return "\(cycle)-minggu-\(seasonSlug)-\(week)"
    }

    /// Extracts the week/Sunday number from strings like "minggu adven i",
    /// "minggu biasa 15", "minggu prapaskah 3", etc.
    private static func extractWeekNumber(from text: String) -> Int? {
        // Arabic digit
        if let match = text.range(of: #"\b(\d{1,2})\b"#, options: .regularExpression) {
            return Int(text[match])
        }
        // Roman numeral (most common in Indonesian lectionary text)
        return parseRoman(from: text)
    }

    private static func parseRoman(from text: String) -> Int? {
        // Find a standalone Roman numeral token at word boundary
        let romanPattern = #"\b(I{1,3}|IV|VI{0,3}|IX|XI{0,3}|XIV|XVI{0,3}|XIX|XXI{0,3}|XXIV|XXVI{0,3}|XXIX|XXX(?:I{0,3}|IV))\b"#
        guard let range = text.uppercased().range(of: romanPattern, options: .regularExpression) else {
            return nil
        }
        let token = String(text.uppercased()[range])
        return romanToInt(token)
    }

    private static func romanToInt(_ s: String) -> Int? {
        let map: [(String, Int)] = [
            ("XXXIV", 34), ("XXXIII", 33), ("XXXII", 32), ("XXXI", 31),
            ("XXX", 30),   ("XXIX", 29),   ("XXVIII", 28), ("XXVII", 27),
            ("XXVI", 26),  ("XXV", 25),    ("XXIV", 24),   ("XXIII", 23),
            ("XXII", 22),  ("XXI", 21),    ("XX", 20),
            ("XIX", 19),   ("XVIII", 18),  ("XVII", 17),   ("XVI", 16),
            ("XV", 15),    ("XIV", 14),    ("XIII", 13),   ("XII", 12),
            ("XI", 11),    ("X", 10),
            ("IX", 9),     ("VIII", 8),    ("VII", 7),     ("VI", 6),
            ("V", 5),      ("IV", 4),      ("III", 3),     ("II", 2), ("I", 1),
        ]
        for (roman, value) in map where s == roman {
            return value
        }
        return nil
    }

    // MARK: - Feast / Solemnity Lookup

    /// Static table mapping lowercased celebration name fragments to lagumisa slugs.
    /// Cycle-sensitive feasts use "{cycle}" placeholder, replaced at call time.
    private static func feastSlug(from lower: String, cycle: String) -> String? {
        let table: [(fragment: String, slug: String)] = [
            // Christmas
            ("hari raya natal",                             "a-hari-raya-natal-siang"),

            // Advent & Christmas season feasts
            ("hari raya santa maria bunda allah",           "a-hari-raya-santa-maria-bunda-allah"),
            ("penampakan tuhan",                            "a-hari-raya-penampakan-tuhan"),
            ("pembaptisan tuhan",                           "{cycle}-pesta-pembaptisan-tuhan"),
            ("keluarga kudus",                              "{cycle}-pesta-keluarga-kudus-yesus-maria-yusuf"),

            // Lent & Holy Week
            ("rabu abu",                                    "{cycle}-rabu-abu"),
            ("minggu palma",                                "a-minggu-palma"),
            ("kamis dalam pekan suci",                      "a-kamis-dalam-pekan-suci"),
            ("kamis putih",                                 "a-kamis-putih"),
            ("jumat agung",                                 "a-jumat-agung"),
            ("malam paskah",                                "a-malam-paskah-1a"),

            // Easter & Pentecost
            ("hari raya paskah",                            "a-hari-raya-paskah"),
            ("kenaikan",                                    "a-hari-raya-kenaikan"),
            ("vigili pentakosta",                           "a-vigili-pentakosta"),
            ("hari raya pentakosta",                        "a-hari-raya-pentakosta"),

            // Solemnities in Ordinary Time
            ("tritunggal",                                  "{cycle}-hari-raya-tritunggal-mahakudus"),
            ("tubuh dan darah kristus",                     "{cycle}-hari-raya-tubuh-dan-darah-kristus"),
            ("hati yesus",                                  "{cycle}-hari-raya-hati-yesus-yang-mahakudus"),

            // Fixed feasts
            ("bertobatnya st. paulus",                      "p-pesta-bertobatnya-st-paulus"),
            ("yesus dipersembahkan",                        "p-pesta-yesus-dipersembahkan-di-kenisah"),
            ("st. yusuf",                                   "p-hari-raya-st-yusuf"),
            ("kabar sukacita",                              "p-hari-raya-kabar-sukacita"),
            ("st. markus",                                  "p-pesta-stmarkus"),
            ("st. filipus",                                 "p-pesta-stfilipus-dan-styakobus"),
            ("st. matias",                                  "p-pesta-stmatias"),
            ("maria mengunjungi",                           "p-pesta-stmaria-mengunjungi-elizabet"),
            ("kelahiran st. yohanes pembaptis",             "p-hari-raya-kelahiran-st-yohanes-pembaptis"),
            ("st. petrus dan paulus",                       "p-hari-raya-st-petrus-dan-paulus"),
            ("st. tomas",                                   "p-pesta-stthomas"),
            ("st. yakobus",                                 "p-pesta-styakobus"),
            ("yesus menampakkan kemuliaannya",              "p-pesta-yesus-menampakkan-kemuliaannya"),
            ("st. laurensius",                              "p-pesta-stlaurensius"),
            ("maria diangkat ke surga",                     "p-hari-raya-spmaria-diangkat-ke-surga"),
            ("kemerdekaan",                                 "p-hari-raya-kemerdekaan"),
            ("st. bartolomeus",                             "p-pesta-stbartolomeus"),
            ("kelahiran santa perawan maria",               "p-pesta-kelahiran-spmaria"),
            ("salib suci",                                  "p-pesta-salib-suci"),
            ("st. matius",                                  "p-pesta-st-matius-rasul-dan-pengarang-injil"),
            ("mikael",                                      "p-pesta-stmikael-gabriel-rafael"),
            ("st. teresia",                                 "p-pesta-stteresia-dari-kanak-kanak-yesus"),
            ("st. fransiskus asisi",                        "p-peringatan-stfransiskus-asisi"),
            ("st. lukas",                                   "p-pesta-stlukas"),
            ("st. simon",                                   "p-pesta-stsimon-yudas"),
            ("semua orang kudus",                           "p-hari-raya-semua-orang-kudus"),
            ("arwah semua orang beriman",                   "p-peringatan-arwah-semua-orang-beriman"),
            ("basilik lateran",                             "p-pesta-pemberkatan-gereja-basilik-lateran"),
            ("st. andreas",                                 "p-pesta-standreas"),
            ("st. fransiskus xaverius",                     "p-pesta-stfransiskus-xaverius"),
            ("maria dikandung tanpa dosa",                  "p-hari-raya-spmaria-dikandung-tanpa-dosa"),
            ("st. stefanus",                                "p-pesta-ststefanus"),
            ("st. yohanes rasul",                           "p-pesta-styohanes"),
            ("kanak-kanak suci",                            "p-pesta-kanak-kanak-suci"),
        ]

        for (fragment, slugTemplate) in table {
            if lower.contains(fragment) {
                let resolved = slugTemplate.replacingOccurrences(of: "{cycle}", with: cycle)
                return resolved
            }
        }
        return nil
    }
}
