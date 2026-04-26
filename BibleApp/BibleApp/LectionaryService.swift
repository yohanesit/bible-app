//  LectionaryService.swift
//  BibleApp
//
//  Fetches daily Catholic Mass lectionary reading references from the
//  cpbjr/catholic-readings-api (GitHub Pages static JSON).
//
//  Endpoint:
//    GET https://cpbjr.github.io/catholic-readings-api/readings/{YEAR}/{MM-DD}.json
//
//  Response example:
//    {
//      "date": "2026-04-11",
//      "season": "Eastertide",
//      "readings": {
//        "firstReading": "Acts 4:13-21",
//        "psalm": "Psalm 118:1 and 14-15ab, 16-18, 19-21",
//        "secondReading": null,
//        "gospel": "Mark 16:9-15"
//      }
//    }
//
//  Returns lightweight citation-only data — no Bible text travels over the
//  network; text is always read from the local BibleDatabase.

import Foundation

// MARK: - Response models (cpbjr API)

private struct CpbjrResponse: Decodable {
    let date: String
    let season: String?
    let readings: CpbjrReadings
}

private struct CpbjrReadings: Decodable {
    let firstReading: String?
    let psalm: String?
    let secondReading: String?
    let gospel: String?
}

// MARK: - Public output models

struct LectionaryDay {
    let celebration: String        // e.g. "Sabtu, Masa Paskah"
    let season: String             // e.g. "Eastertide"
    let readings: [LectionaryReadingRef]
}

struct LectionaryReadingRef {
    let type: String       // e.g. "first_reading", "gospel"
    let citation: String   // e.g. "Acts 5:27-33"
    let intro: String?     // nil — derived locally in DailyReadingProvider
}

// MARK: - LectionaryServiceError

enum LectionaryServiceError: LocalizedError {
    case badURL
    case networkError(Error)
    case decodingError(Error)
    case noReadings
    case notCovered(Date)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Could not build the lectionary URL."
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        case .decodingError(let e):
            return "Could not read lectionary data: \(e.localizedDescription)"
        case .noReadings:
            return "No readings found for this date."
        case .notCovered(let d):
            return "Lectionary data not available for \(d.formatted(.dateTime.day().month().year()))."
        }
    }
}

// MARK: - LectionaryService

final class LectionaryService {

    static let shared = LectionaryService()

    private let baseURL = "https://cpbjr.github.io/catholic-readings-api/readings"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    /// Root directory for on-disk lectionary cache: Library/Caches/lectionary/
    private let cacheRoot: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("lectionary", isDirectory: true)
    }()

    private init() {
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// Fetch lectionary for `date`. Tries network first; on failure falls back to disk cache.
    func fetchDay(date: Date) async throws -> LectionaryDay {
        let cal = Calendar.current
        let year  = cal.component(.year,  from: date)
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)

        let mmdd = String(format: "%02d-%02d", month, day)
        let urlString = "\(baseURL)/\(year)/\(mmdd).json"

        guard let url = URL(string: urlString) else {
            throw LectionaryServiceError.badURL
        }

        // Try network; on failure fall back to disk cache.
        let data: Data
        do {
            let (d, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                // Not covered by the API — check disk cache before giving up.
                if let cached = readFromDiskCache(year: year, mmdd: mmdd) {
                    data = cached
                } else {
                    throw LectionaryServiceError.notCovered(date)
                }
            } else {
                data = d
                // Persist to disk so future offline launches can use it.
                writeToDiskCache(data: data, year: year, mmdd: mmdd)
            }
        } catch let e as LectionaryServiceError {
            throw e
        } catch {
            // Network error — try disk cache.
            if let cached = readFromDiskCache(year: year, mmdd: mmdd) {
                data = cached
            } else {
                throw LectionaryServiceError.networkError(error)
            }
        }

        let raw: CpbjrResponse
        do {
            raw = try JSONDecoder().decode(CpbjrResponse.self, from: data)
        } catch {
            throw LectionaryServiceError.decodingError(error)
        }

        // Build reading refs array from the flat readings object
        var refs: [LectionaryReadingRef] = []

        if let citation = raw.readings.firstReading, !citation.isEmpty {
            refs.append(LectionaryReadingRef(type: "first_reading", citation: citation, intro: nil))
        }
        if let citation = raw.readings.psalm, !citation.isEmpty {
            refs.append(LectionaryReadingRef(type: "responsorial_psalm", citation: citation, intro: nil))
        }
        if let citation = raw.readings.secondReading, !citation.isEmpty {
            refs.append(LectionaryReadingRef(type: "second_reading", citation: citation, intro: nil))
        }
        if let citation = raw.readings.gospel, !citation.isEmpty {
            refs.append(LectionaryReadingRef(type: "gospel", citation: citation, intro: nil))
        }

        if refs.isEmpty { throw LectionaryServiceError.noReadings }

        let season   = raw.season ?? "Ordinary Time"
        let dayName  = LectionaryService.buildCelebrationName(date: date, season: season)

        return LectionaryDay(celebration: dayName, season: season, readings: refs)
    }

    /// Pre-fetch and cache all days in `year` that are not already on disk.
    /// Runs silently in the background — caller does not need to await results.
    func prefetchYearIfNeeded(_ year: Int) async {
        let cal = Calendar.current
        guard var date = DateComponents(calendar: cal, year: year, month: 1, day: 1).date else { return }
        let end  = DateComponents(calendar: cal, year: year + 1, month: 1, day: 1).date ?? date

        while date < end {
            let month = cal.component(.month, from: date)
            let day   = cal.component(.day,   from: date)
            let mmdd  = String(format: "%02d-%02d", month, day)

            // Skip if already cached on disk.
            if readFromDiskCache(year: year, mmdd: mmdd) == nil {
                _ = try? await fetchDay(date: date)
            }

            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
    }

    // MARK: - Disk cache helpers

    private func cacheURL(year: Int, mmdd: String) -> URL {
        let yearDir = cacheRoot.appendingPathComponent("\(year)", isDirectory: true)
        try? FileManager.default.createDirectory(at: yearDir, withIntermediateDirectories: true)
        return yearDir.appendingPathComponent("\(mmdd).json")
    }

    private func writeToDiskCache(data: Data, year: Int, mmdd: String) {
        let url = cacheURL(year: year, mmdd: mmdd)
        try? data.write(to: url, options: .atomic)
    }

    private func readFromDiskCache(year: Int, mmdd: String) -> Data? {
        let url = cacheURL(year: year, mmdd: mmdd)
        return try? Data(contentsOf: url)
    }

    // MARK: - Helpers

    /// Builds a human-readable celebration name in Indonesian from the date + season.
    /// Example: "Sabtu, Masa Paskah"
    /// Static so BundledLectionaryStore can reuse it without a network-service instance.
    static func buildCelebrationName(date: Date, season: String) -> String {
        let cal      = Calendar.current
        let weekday  = cal.component(.weekday, from: date)
        let dayName  = indonesianWeekday(weekday)
        let seasonID = indonesianSeason(season)
        return "\(dayName), \(seasonID)"
    }

    private static func indonesianWeekday(_ weekday: Int) -> String {
        // weekday: 1=Sunday … 7=Saturday (Gregorian)
        switch weekday {
        case 1: return "Minggu"
        case 2: return "Senin"
        case 3: return "Selasa"
        case 4: return "Rabu"
        case 5: return "Kamis"
        case 6: return "Jumat"
        case 7: return "Sabtu"
        default: return "Hari"
        }
    }

    private static func indonesianSeason(_ raw: String) -> String {
        switch raw.lowercased() {
        case "eastertide", "easter":  return "Masa Paskah"
        case "lent":                  return "Masa Prapaskah"
        case "advent":                return "Masa Adven"
        case "christmas":             return "Masa Natal"
        case "ordinary time",
             "ordinarytime",
             "ordinary":             return "Masa Biasa"
        default:                      return raw
        }
    }
}
