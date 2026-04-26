//  BundledLectionaryStore.swift
//  BibleApp
//
//  Reads pre-generated lectionary JSON files from the app bundle and resolves
//  regional overrides, returning LectionaryDay values without any network call.
//
//  Resolution order for a given (date, region):
//    1. Check lectionary_overrides.json → overrides[region][year][MM-DD]
//    2. Else check lectionary_YYYY.json → days[MM-DD]
//    3. Return nil if neither covers the date (caller falls back to network)
//
//  Year files are lazily loaded and cached in memory (one per year ~44 KB).
//  The overrides file is loaded once on first use (~5 KB).
//
//  KMP note: This class has zero UIKit/SwiftUI/Foundation-UI dependencies.
//  The port to Kotlin commonMain is a straight 1:1 translation:
//    - Bundle.main.url → expect fun loadResource(name: String): String (actual per platform)
//    - JSONDecoder → kotlinx.serialization
//    - Calendar.current.component → java.time.LocalDate

import Foundation

// MARK: - BundledLectionaryStore

final class BundledLectionaryStore {

    static let shared = BundledLectionaryStore()

    // MARK: - Private state

    private var yearCache:      [Int: LectionaryBundleFile]  = [:]
    private var overridesCache: LectionaryOverridesFile?
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Public API

    /// Returns a LectionaryDay built from bundled data for the given date and
    /// region code (e.g. "ID", "US"). Returns nil if the date is not covered
    /// by any bundle file — the caller should fall back to the network.
    func day(for date: Date, region: String) -> LectionaryDay? {
        let cal   = Calendar.current
        let year  = cal.component(.year,  from: date)
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        let mmdd  = String(format: "%02d-%02d", month, day)

        // 1. Try regional override first
        if let bundledDay = resolveOverride(region: region, year: year, mmdd: mmdd) {
            return makeLectionaryDay(from: bundledDay, date: date)
        }

        // 2. Try base year file
        guard let yearFile = loadYear(year),
              let bundledDay = yearFile.days[mmdd]
        else { return nil }

        return makeLectionaryDay(from: bundledDay, date: date)
    }

    /// All region codes and their display info from the overrides file.
    /// Returns an empty dict if the overrides file cannot be loaded.
    var availableRegions: [String: RegionInfo] {
        loadOverrides()?.regions ?? [:]
    }

    // MARK: - Private: override resolution

    private func resolveOverride(region: String, year: Int, mmdd: String) -> BundledDay? {
        guard let overrides = loadOverrides() else { return nil }
        return overrides.overrides[region]?[String(year)]?[mmdd]
    }

    // MARK: - Private: lazy loaders

    private func loadYear(_ year: Int) -> LectionaryBundleFile? {
        if let cached = yearCache[year] { return cached }
        guard
            let url  = Bundle.main.url(forResource: "lectionary_\(year)", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? decoder.decode(LectionaryBundleFile.self, from: data)
        else {
            print("📖 [Bundle] lectionary_\(year).json not found in bundle")
            return nil
        }
        yearCache[year] = file
        print("📖 [Bundle] Loaded lectionary_\(year).json — \(file.days.count) days")
        return file
    }

    private func loadOverrides() -> LectionaryOverridesFile? {
        if let cached = overridesCache { return cached }
        guard
            let url  = Bundle.main.url(forResource: "lectionary_overrides", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? decoder.decode(LectionaryOverridesFile.self, from: data)
        else {
            print("📖 [Bundle] lectionary_overrides.json not found in bundle")
            return nil
        }
        overridesCache = file
        print("📖 [Bundle] Loaded overrides — \(file.regions.count) region(s)")
        return file
    }

    // MARK: - Private: model mapping

    private func makeLectionaryDay(from bundled: BundledDay, date: Date) -> LectionaryDay {
        // Map the fixed-position r array to typed reading refs
        var refs: [LectionaryReadingRef] = []
        let types = ["first_reading", "responsorial_psalm", "second_reading", "gospel"]

        for (index, readingType) in types.enumerated() {
            guard index < bundled.r.count,
                  let citation = bundled.r[index],
                  !citation.isEmpty
            else { continue }
            refs.append(LectionaryReadingRef(type: readingType, citation: citation, intro: nil))
        }

        // Use explicit celebration name if provided; otherwise derive from weekday + season
        let celebration = bundled.celebration
            ?? LectionaryService.buildCelebrationName(date: date, season: bundled.s)

        return LectionaryDay(
            celebration: celebration,
            season: bundled.s,
            readings: refs
        )
    }
}
