//  BundledLectionary.swift
//  BibleApp
//
//  Decodable models for the offline lectionary bundle files.
//  These map directly to the compact JSON format produced by
//  scripts/generate_lectionary_bundle.py.
//
//  No I/O lives here — this file is pure value types.
//
//  KMP note: These structs map 1:1 to Kotlin data classes.
//  When the Android port begins, replicate as:
//    data class LectionaryBundleFile(val year: Int, val generatedAt: String, val days: Map<String, BundledDay>)
//    data class BundledDay(val s: String, val r: List<String?>, val celebration: String? = null)
//    data class RegionInfo(val name: String, val flag: String)

import Foundation

// MARK: - Base year file

/// Top-level structure of `lectionary_YYYY.json` bundle files.
/// Each file covers one calendar year; keys in `days` are "MM-DD".
struct LectionaryBundleFile: Decodable {
    let year: Int
    let generatedAt: String
    let days: [String: BundledDay]          // key: "MM-DD" e.g. "04-05"
}

/// One day's lectionary citations in compact form.
///
/// `r` is always length-4 with fixed positions:
///   index 0 = firstReading
///   index 1 = responsorialPsalm
///   index 2 = secondReading  (nil on ferias — no second reading)
///   index 3 = gospel
///
/// `celebration` is optional. When present it overrides the auto-generated
/// "Weekday, Season" name (used for region-specific feast day names).
struct BundledDay: Decodable {
    let s: String               // season raw string (matches cpbjr / LiturgicalSeason mapping)
    let r: [String?]            // fixed-length 4: [first, psalm, second, gospel]
    let celebration: String?    // optional display-name override
}

// MARK: - Regional overrides file

/// Top-level structure of `lectionary_overrides.json`.
/// Contains region metadata and per-region, per-year date patches.
struct LectionaryOverridesFile: Decodable {
    let regions: [String: RegionInfo]

    /// overrides[regionCode][yearString][MM-DD] = BundledDay
    /// e.g. overrides["ID"]["2026"]["06-07"] = Corpus Christi entry
    let overrides: [String: [String: [String: BundledDay]]]
}

/// Metadata for a supported lectionary region.
struct RegionInfo: Decodable {
    let name: String    // e.g. "Indonesia (KWI)"
    let flag: String    // e.g. "🇮🇩"
}
