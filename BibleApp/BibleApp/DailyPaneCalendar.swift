//  DailyPaneCalendar.swift
//  BibleApp
//
//  Single source of truth for dates shown in the right pane vs. parsing
//  `selectedRightLabel` in ContentView — avoids locale / off-by-one mismatches.

import Foundation

enum DailyPaneCalendar {
    static let pastDays = 7
    static let futureDays = 2

    /// Same window as `RightPaneView` (past … today … future).
    static func dayRangeEntries() -> [(date: Date, label: String)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-pastDays ... futureDays).compactMap { offset -> (Date, String)? in
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            let label = d.formatted(.dateTime.day().month(.wide))
            return (d, label)
        }
    }

    static func date(forLabel raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return dayRangeEntries().first {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }?.date
    }

    static var todayFormattedLabel: String {
        Calendar.current.startOfDay(for: Date()).formatted(.dateTime.day().month(.wide))
    }

    /// Long-form date for sidebar subtitle (e.g. "April 23, 2026"), locale-aware.
    static func longDisplayDate(forLabel label: String?) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return longDisplayDate(for: Calendar.current.startOfDay(for: Date()))
        }
        if let d = date(forLabel: trimmed) {
            return longDisplayDate(for: d)
        }
        return longDisplayDate(for: Calendar.current.startOfDay(for: Date()))
    }

    private static func longDisplayDate(for date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day().year())
    }

    /// Day-of-month for compact calendar cells (1…31).
    static func dayOfMonth(forLabel label: String) -> Int? {
        guard let d = date(forLabel: label) else { return nil }
        return Calendar.current.component(.day, from: d)
    }
}
