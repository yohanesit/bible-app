//  ReferenceParser.swift
//  BibleApp
//
//  Parses a Bible reference string as returned by the Lectio API into
//  a structured form that can be used to look up text in BibleDatabase.
//
//  Handles:
//    "Acts 5:27-33"              → chapter 5, verses 27–33
//    "Acts 2:14, 22-33"          → chapter 2, verses 14 and 22–33
//    "Psalm 34:2-3, 17-18, 19"   → chapter 34, verses 2–3, 17–18, 19
//    "John 3:31-36"              → chapter 3, verses 31–36
//    "Genesis 1"                 → full chapter 1 (no verse filter)

import Foundation

// MARK: - ParsedReference

struct ParsedReference {
    let bookName: String            // as received, e.g. "Acts"
    let chapter: Int
    /// Empty means "whole chapter".
    let verseRanges: [ClosedRange<Int>]

    /// All individual verse numbers covered (sorted, deduplicated).
    var allVerses: [Int] {
        guard !verseRanges.isEmpty else { return [] }
        return Array(Set(verseRanges.flatMap { Array($0) })).sorted()
    }
}

// MARK: - ResponsorialParsed

struct ResponsorialParsed {
    let bookName: String
    let chapter: Int
    /// Verse ranges for the refrain (the verse before "and" in the citation).
    let refrainRanges: [ClosedRange<Int>]
    /// Each element is the verse ranges for one strophe block.
    let stropheGroups: [[ClosedRange<Int>]]
}

// MARK: - ReferenceParser

enum ReferenceParser {

    /// Parse a Lectio API citation string into a `ParsedReference`.
    /// Returns `nil` if the string is unrecognizable.
    static func parse(_ raw: String) -> ParsedReference? {
        // Normalize: collapse multiple spaces, trim
        let s = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Split at the last colon that is followed by digits (chapter:verse boundary).
        // We look for the pattern "BookName Chapter:VerseSpec" or "BookName Chapter".
        //
        // Strategy: find the colon separating chapter from verses.
        // The book name may contain digits (e.g. "1 John"), so we can't simply split on
        // the first space. Instead we use a regex.

        // Pattern: optional number prefix + book name + whitespace + chapter + optional :verses
        // Capture groups: (1) full book+chapter, (2) chapter number, (3) verse spec (optional)
        let pattern = #"^(.*?)\s+(\d+)(?::(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: s, range: NSRange(s.startIndex..., in: s)
              )
        else { return nil }

        guard
            let bookRange    = Range(match.range(at: 1), in: s),
            let chapterRange = Range(match.range(at: 2), in: s),
            let chapter      = Int(s[chapterRange])
        else { return nil }

        let bookName = String(s[bookRange])
        let verseSpec: String? = {
            let r = match.range(at: 3)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
            return String(s[range])
        }()

        let ranges = verseSpec.map { parseVerseSpec($0) } ?? []
        return ParsedReference(bookName: bookName, chapter: chapter, verseRanges: ranges)
    }

    // MARK: - Verse spec parsing

    /// Parse a verse specification like "14, 22-33" or "2-3, 17-18, 19".
    /// Also handles "1 and 14-15ab, 16-18" (USCCB/Catholic psalm notation).
    /// Individual verse numbers are treated as single-element ranges (n...n).
    private static func parseVerseSpec(_ spec: String) -> [ClosedRange<Int>] {
        // Normalize USCCB "and" connector → comma (e.g. "1 and 14-15ab" → "1,14-15ab")
        let normalized = spec
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " AND ", with: ",")

        // Remove letter suffixes (e.g. "2a" → "2", "14b" → "14", "15ab" → "15")
        let cleaned = normalized.replacingOccurrences(of: "[a-zA-Z]", with: "",
                                                      options: .regularExpression)
        var result: [ClosedRange<Int>] = []

        for part in cleaned.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let ends = trimmed.components(separatedBy: "-")
                if ends.count == 2,
                   let lo = Int(ends[0].trimmingCharacters(in: .whitespaces)),
                   let hi = Int(ends[1].trimmingCharacters(in: .whitespaces)),
                   lo <= hi {
                    result.append(lo...hi)
                }
            } else if let v = Int(trimmed) {
                result.append(v...v)
            }
        }

        return result
    }

    // MARK: - Responsorial psalm parsing

    /// Parse a psalm citation that contains an "and" separator marking the refrain verse.
    /// Returns nil if no "and" is found — caller should fall back to plain `parse()`.
    ///
    /// Example: "Psalm 118:1 and 14-15ab, 16-18, 19-21"
    ///   → refrainRanges: [1...1]
    ///   → stropheGroups: [[14...15], [16...18], [19...21]]
    static func parseResponsorial(_ raw: String) -> ResponsorialParsed? {
        let s = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let pattern = #"^(.*?)\s+(\d+)(?::(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }

        guard
            let bookRange    = Range(match.range(at: 1), in: s),
            let chapterRange = Range(match.range(at: 2), in: s),
            let chapter      = Int(s[chapterRange])
        else { return nil }

        let bookName = String(s[bookRange])

        let r = match.range(at: 3)
        guard r.location != NSNotFound, let vsRange = Range(r, in: s) else { return nil }
        let verseSpec = String(s[vsRange])

        guard let andRange = verseSpec.range(of: " and ", options: .caseInsensitive) else {
            return nil
        }

        let refrainSpec  = String(verseSpec[verseSpec.startIndex..<andRange.lowerBound])
        let strophesSpec = String(verseSpec[andRange.upperBound...])

        let refrainRanges = parseVerseSpec(refrainSpec)
        guard !refrainRanges.isEmpty else { return nil }

        let stropheGroups: [[ClosedRange<Int>]] = strophesSpec
            .components(separatedBy: ",")
            .compactMap { part in
                let ranges = parseVerseSpec(part.trimmingCharacters(in: .whitespaces))
                return ranges.isEmpty ? nil : ranges
            }
        guard !stropheGroups.isEmpty else { return nil }

        return ResponsorialParsed(
            bookName: bookName,
            chapter: chapter,
            refrainRanges: refrainRanges,
            stropheGroups: stropheGroups
        )
    }
}
