//  DailyReadingProvider.swift
//  BibleApp
//
//  Orchestrates LectionaryService + BibleDatabase to produce a MassDay
//  ready for display. Injected into the SwiftUI environment at the app root.
//
//  Flow:
//   1. loadDay(date) is called (e.g. on app open or date selection)
//   2. Check in-memory cache
//   3. Fetch reading references from LectionaryService (lightweight API call)
//   4. Look up each reference in local BibleDatabase (no network)
//   5. Assemble MassDay and cache it
//
//  States exposed to the UI:
//    .loading     — fetch in progress
//    .loaded      — MassDay ready
//    .needsSync   — Lectio data arrived but Bible text not in local DB
//    .offline     — Lectio API call failed; returns cached day if available
//    .error       — unrecoverable problem

import Foundation
import Observation

// MARK: - Load state

enum DayLoadState: Equatable {
    case idle
    case loading
    case loaded(MassDay)
    case needsSync(MassDay)   // Lectio worked but text missing; MassDay has placeholder text
    case offline(MassDay)     // network failed; showing cached or sample fallback
    case error(String)

    static func == (lhs: DayLoadState, rhs: DayLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading): return true
        case (.error(let a), .error(let b)):        return a == b
        default: return false
        }
    }

    var massDay: MassDay? {
        switch self {
        case .loaded(let d), .needsSync(let d), .offline(let d): return d
        default: return nil
        }
    }
}

// MARK: - DailyReadingProvider

@Observable
final class DailyReadingProvider {

    var state: DayLoadState = .idle

    // Current date being displayed (set by ContentView when date selection changes).
    var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Stable token for SwiftUI when the visible `MassDay` changes (syncs right-pane label).
    var loadedMassDayTimeInterval: TimeInterval {
        switch state {
        case .loaded(let d), .needsSync(let d), .offline(let d):
            return d.date.timeIntervalSince1970
        default:
            return -1
        }
    }

    private var cache: [String: MassDay] = [:]
    private let lectionary = LectionaryService.shared
    private let db = BibleDatabase.shared

    // MARK: - Public

    func clearCache() {
        cache = [:]
        state = .idle
    }

    func loadDay(_ date: Date) async {
        let day = Calendar.current.startOfDay(for: date)
        await MainActor.run { selectedDate = day }

        let key = cacheKey(for: day)

        // Instant hit from memory cache
        if let cached = cache[key] {
            await MainActor.run { state = .loaded(cached) }
            return
        }

        await MainActor.run { state = .loading }

        // ── Bundle-first: serve from local data, no network needed ───────────
        let region = UserDefaults.standard.string(forKey: "lectionaryRegion") ?? "ID"
        if let bundled = BundledLectionaryStore.shared.day(for: day, region: region) {
            print("📖 [Bundle] Hit for \(key) [\(region)] — offline ✓")
            let (massDay, hasAllText) = assemble(from: bundled, date: day)
            cache[key] = massDay
            await MainActor.run {
                state = hasAllText ? .loaded(massDay) : .needsSync(massDay)
            }
            return
        }
        // ── End bundle-first ─────────────────────────────────────────────────

        do {
            // Step 1: Fetch reading references from Lectio API (cpbjr)
            print("📖 [Lectio] Fetching readings for \(key)…")
            let lectionaryDay = try await lectionary.fetchDay(date: day)
            print("✅ [Lectio] Got '\(lectionaryDay.celebration)' | season: \(lectionaryDay.season) | \(lectionaryDay.readings.count) reading(s)")
            for ref in lectionaryDay.readings {
                print("   → [\(ref.type)] \(ref.citation)")
            }

            // Step 2: Assemble MassDay by looking up text locally
            let (massDay, hasAllText) = assemble(from: lectionaryDay, date: day)
            print(hasAllText
                  ? "✅ [DB] All text found locally — showing real readings"
                  : "⚠️ [DB] Some text missing — sync needed")

            cache[key] = massDay

            await MainActor.run {
                state = hasAllText ? .loaded(massDay) : .needsSync(massDay)
            }

        } catch {
            print("❌ [Lectio] Failed: \(error.localizedDescription)")
            // Network failed — try cache or fall back to sample
            if let cached = cache[key] {
                await MainActor.run { state = .offline(cached) }
            } else {
                // For today, show the sample so the app isn't blank on first install
                let isToday = Calendar.current.isDateInToday(day)
                let fallback = isToday ? MassDay.sample : makePlaceholderDay(date: day)
                await MainActor.run { state = .offline(fallback) }
            }
        }
    }

    // MARK: - Assembly

    private func assemble(from day: LectionaryDay,
                          date: Date) -> (MassDay, hasAllText: Bool) {
        var readings: [MassReading] = []
        var missingText = false

        for ref in day.readings {
            let readingType = BookNameMapper.readingType(from: ref.type)

            // Parse the citation ("Acts 5:27-33")
            guard let parsed = ReferenceParser.parse(ref.citation) else { continue }

            // Map English book name to our DB slug + Indonesian name
            let bookInfo = BookNameMapper.info(forEnglish: parsed.bookName)
            let indonesianRef = buildIndonesianReference(
                bookInfo: bookInfo,
                parsed: parsed
            )

            // Look up text locally
            let bodyText: String

            if readingType == .psalm {
                let (text, missing) = buildPsalmBodyText(
                    citation: ref.citation,
                    bookInfo: bookInfo,
                    parsedFallback: parsed
                )
                bodyText = text
                if missing { missingText = true }
            } else if let slug = bookInfo?.slug,
                      let text = db.passage(
                        bookSlug: slug,
                        chapter: parsed.chapter,
                        verseRanges: parsed.verseRanges
                      ) {
                bodyText = text
            } else {
                bodyText = "Teks belum tersedia. Silakan sinkronkan Alkitab melalui Pengaturan > Admin > Sinkronkan Alkitab."
                missingText = true
            }

            // Build intro rubric: use API-provided intro if available, otherwise derive from BookInfo
            let introRubric = deriveIntroRubric(
                apiIntro: ref.intro,
                bookInfo: bookInfo,
                readingType: readingType
            )

            // Response rubric for readings + gospel
            let responseRubric: String?
            let congregationResponse: String?

            if readingType == .gospel {
                responseRubric       = "Demikianlah Injil Tuhan."
                congregationResponse = "Terpujilah Kristus."
            } else if readingType == .firstReading || readingType == .secondReading {
                responseRubric       = "Demikianlah sabda Tuhan."
                congregationResponse = "Syukur kepada Allah."
            } else {
                responseRubric       = nil
                congregationResponse = nil
            }

            readings.append(MassReading(
                type: readingType,
                reference: indonesianRef,
                introRubric: introRubric,
                bodyText: bodyText,
                responseRubric: responseRubric,
                congregationResponse: congregationResponse
            ))
        }

        let season = BookNameMapper.season(from: day.season)
        let massDay = MassDay(
            date: date,
            celebrationName: day.celebration,
            season: season,
            readings: readings
        )

        return (massDay, hasAllText: !missingText)
    }

    // MARK: - Helpers

    private func buildIndonesianReference(bookInfo: BookInfo?,
                                          parsed: ParsedReference) -> String {
        let bookName = bookInfo?.indonesianName ?? parsed.bookName
        let chapterAndVerses = buildVerseString(parsed: parsed)
        return "\(bookName) \(chapterAndVerses)"
    }

    private func buildVerseString(parsed: ParsedReference) -> String {
        guard !parsed.verseRanges.isEmpty else { return "\(parsed.chapter)" }

        let verseSpec = parsed.verseRanges.map { range -> String in
            if range.lowerBound == range.upperBound {
                return "\(range.lowerBound)"
            } else {
                return "\(range.lowerBound)-\(range.upperBound)"
            }
        }.joined(separator: ", ")

        return "\(parsed.chapter):\(verseSpec)"
    }

    private func deriveIntroRubric(apiIntro: String?,
                                   bookInfo: BookInfo?,
                                   readingType: ReadingType) -> String {
        // Psalm: always the same
        if readingType == .psalm { return "Mazmur Tanggapan." }

        // Gospel: always the same pattern, derived from BookInfo
        if readingType == .gospel {
            return bookInfo?.introRubric
                ?? "Inilah Injil Yesus Kristus."
        }

        // For other readings, prefer BookInfo's Indonesian rubric
        return bookInfo?.introRubric ?? (apiIntro.map { _ in "" } ?? "Bacaan dari Kitab Suci.")
    }

    /// Build bodyText for a responsorial psalm, inserting "R. [refrain]" between strophes.
    /// Falls back to plain verse text when the citation has no "and" separator.
    private func buildPsalmBodyText(
        citation: String,
        bookInfo: BookInfo?,
        parsedFallback: ParsedReference
    ) -> (text: String, missing: Bool) {
        let placeholder = "Teks belum tersedia. Silakan sinkronkan Alkitab melalui Pengaturan > Admin > Sinkronkan Alkitab."
        guard let slug = bookInfo?.slug else { return (placeholder, true) }

        guard let responsorial = ReferenceParser.parseResponsorial(citation) else {
            // No "and" in citation — plain verse lookup
            if let text = db.passage(bookSlug: slug, chapter: parsedFallback.chapter,
                                     verseRanges: parsedFallback.verseRanges) {
                return (text, false)
            }
            return (placeholder, true)
        }

        guard let refrainText = db.passage(bookSlug: slug, chapter: responsorial.chapter,
                                           verseRanges: responsorial.refrainRanges) else {
            return (placeholder, true)
        }

        var parts: [String] = []
        var missing = false
        for stropheRanges in responsorial.stropheGroups {
            parts.append("R. \(refrainText)")
            if let stropheText = db.passage(bookSlug: slug, chapter: responsorial.chapter,
                                            verseRanges: stropheRanges) {
                parts.append(stropheText)
            } else {
                parts.append(placeholder)
                missing = true
            }
        }
        parts.append("R. \(refrainText)")

        return (parts.joined(separator: "\n\n"), missing)
    }

    private func makePlaceholderDay(date: Date) -> MassDay {
        MassDay(
            date: date,
            celebrationName: date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
            season: .ordinaryTime,
            readings: []
        )
    }

    private func cacheKey(for date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year!)-\(comps.month!)-\(comps.day!)"
    }
}
