//  BibleSource.swift
//  BibleApp
//
//  Which on-disk translation tree to use (Preferences › Bible Source).
//  Kept in its own file so all targets and incremental builds resolve the type reliably.

import Foundation

enum BibleSource: String, CaseIterable {
    case alkitab = "alkitab"

    /// Subdirectory under `Documents/bible/`.
    var storageDirName: String {
        switch self {
        case .alkitab: return "tb"
        }
    }
}
