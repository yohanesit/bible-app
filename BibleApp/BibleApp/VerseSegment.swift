//  VerseSegment.swift
//  BibleApp
//
//  KMP note: Mirror as data classes with equivalent fields.

import Foundation

// A single displayable clause within a verse — the highlight granularity unit.
struct LineSegment: Identifiable, Codable, Sendable {
    let id: String                    // "{verseId}_L{index}"
    let text: String
    let estimatedDurationSecs: Double
}

struct VerseSegment: Identifiable, Codable, Sendable {
    let id: String                       // "{readingId}_{verseNumber}"
    let number: Int                      // 1-based verse number within the reading
    let text: String                     // full verse text
    let anchorPhrase: [String]           // 3–5 content words stripped of stop words
    let estimatedDurationSecs: Double    // total verse duration (sum of lines)
    let lines: [LineSegment]             // clause-split segments for line-by-line sync
}
