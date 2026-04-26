//  AnchorExtractor.swift
//  BibleApp
//
//  Pure functions — no iOS/Apple imports. KMP extraction target.
//
//  Responsibilities:
//   • Strip Indonesian stop words and affixes from verse text
//   • Extract a 3–5 word anchor phrase fingerprint per verse
//   • Estimate reading duration from word count
//   • Build [VerseSegment] from raw (number, text) pairs

import Foundation

enum AnchorExtractor {

    static let defaultWPM: Double = 110

    // MARK: - Public API

    /// Build VerseSegments from raw (verseNumber, verseText) pairs.
    /// `readingId` is the UUID string of the parent MassReading.
    static func buildSegments(
        readingId: String,
        verses: [(number: Int, text: String)],
        wpm: Double = defaultWPM
    ) -> [VerseSegment] {
        verses.map { verse in
            let verseId = "\(readingId)_\(verse.number)"
            let clauses = splitIntoLines(verse.text)
            let lines = clauses.enumerated().map { idx, clause in
                let wc = countWords(in: clause)
                return LineSegment(
                    id: "\(verseId)_L\(idx)",
                    text: clause,
                    estimatedDurationSecs: estimateDuration(wordCount: wc, wpm: wpm)
                )
            }
            let totalDuration = lines.reduce(0) { $0 + $1.estimatedDurationSecs }
            return VerseSegment(
                id: verseId,
                number: verse.number,
                text: verse.text,
                anchorPhrase: extractAnchor(from: verse.text),
                estimatedDurationSecs: totalDuration,
                lines: lines
            )
        }
    }

    /// Build an AnchorSet from a completed array of VerseSegments.
    static func buildAnchorSet(from segments: [[VerseSegment]]) -> AnchorSet {
        var phrases: [String: [String]] = [:]
        var durations: [String: Double] = [:]
        for group in segments {
            for seg in group {
                phrases[seg.id]   = seg.anchorPhrase
                durations[seg.id] = seg.estimatedDurationSecs
            }
        }
        return AnchorSet(phrases: phrases, durations: durations)
    }

    // MARK: - Anchor extraction

    static func extractAnchor(from text: String) -> [String] {
        let tokens = text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap { stripPunctuation($0) }
            .map { stripSuffix($0) }
            .filter { !stopWords.contains($0) && $0.count >= 3 }
        return Array(tokens.prefix(5))
    }

    // MARK: - Duration estimation

    static func estimateDuration(wordCount: Int, wpm: Double = defaultWPM) -> Double {
        guard wpm > 0 else { return 0 }
        return Double(wordCount) / wpm * 60.0
    }

    // MARK: - Line splitting

    /// Split verse text into readable clauses for line-by-line sync highlighting.
    /// Splits on strong punctuation first (. ! ? ; :), then on commas if chunk > 65 chars.
    static func splitIntoLines(_ text: String, longChunkThreshold: Int = 65) -> [String] {
        // Step 1: split on strong punctuation followed by a space
        var chunks: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)
            let isStrongPunct = ".!?;:".contains(ch)
            let nextIsSpace = i + 1 < chars.count && chars[i + 1] == " "
            let isLastChar = i == chars.count - 1
            if isStrongPunct && (nextIsSpace || isLastChar) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { chunks.append(trimmed) }
                current = ""
                if nextIsSpace { i += 1 }  // skip the space
            }
            i += 1
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { chunks.append(tail) }

        // Step 2: split long chunks further on commas
        var result: [String] = []
        for chunk in chunks {
            if chunk.count > longChunkThreshold {
                result.append(contentsOf: splitOnCommas(chunk))
            } else {
                result.append(chunk)
            }
        }
        return result.filter { !$0.isEmpty }
    }

    private static func splitOnCommas(_ text: String, targetLength: Int = 50) -> [String] {
        let parts = text.components(separatedBy: ", ")
        var result: [String] = []
        var current = ""
        for part in parts {
            let candidate = current.isEmpty ? part : current + ", " + part
            if candidate.count > targetLength && !current.isEmpty {
                result.append(current)
                current = part
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Private helpers

    private static func countWords(in text: String) -> Int {
        text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
    }

    private static let punctuation = CharacterSet(charactersIn: ".,;:!?\"'()[]{}–—«»…\u{2018}\u{2019}\u{201C}\u{201D}")

    private static func stripPunctuation(_ word: String) -> String? {
        let stripped = word.trimmingCharacters(in: punctuation)
        return stripped.isEmpty ? nil : stripped
    }

    // Common Indonesian suffixes on content words
    private static func stripSuffix(_ word: String) -> String {
        let suffixes = ["nya", "ku", "mu", "lah", "kah", "pun"]
        for suffix in suffixes {
            if word.hasSuffix(suffix), word.count > suffix.count + 2 {
                return String(word.dropLast(suffix.count))
            }
        }
        return word
    }

    // MARK: - Indonesian stop word list

    private static let stopWords: Set<String> = [
        // Conjunctions & prepositions
        "yang", "dan", "di", "ke", "dari", "dengan", "untuk", "pada",
        "ini", "itu", "adalah", "akan", "telah", "sudah", "juga",
        "tidak", "bagi", "oleh", "atau", "karena", "maka", "sebagai",
        "bahwa", "serta", "namun", "tetapi", "tapi", "agar", "supaya",
        "hingga", "sampai", "sejak", "ketika", "setelah", "sebelum",
        "apabila", "jika", "bila", "kalau", "meski", "walaupun",
        "sehingga", "walau",
        // Pronouns
        "ia", "aku", "kamu", "mereka", "kami", "kita", "saya",
        "engkau", "dia", "beliau", "anda",
        // Articles / particles
        "si", "sang", "para", "suatu", "sebuah", "seorang",
        // Auxiliaries
        "ada", "bisa", "dapat", "harus", "mau", "ingin", "boleh",
        "perlu", "sedang",
        // Common short words (will also be caught by length filter)
        "pun", "lah", "kah",
        // Liturgical filler words that appear across many verses
        "demikian", "berkata", "maka",
    ]
}
