import SwiftUI
import UIKit

// MARK: - Layout

var hPageMargin: CGFloat { UIDevice.current.userInterfaceIdiom == .pad ? 48 : 24 }

// MARK: - Theme

enum AppTheme: String, CaseIterable {
    case purba
    case abadi
    case kini
    case system

    var displayName: String {
        switch self {
        case .purba:   return "Classic"
        case .abadi:   return "Roman"
        case .kini:    return "Modern"
        case .system:  return "System"
        }
    }
}

enum AppMode {
    case day
    case night
}

enum AppColorScheme: String, CaseIterable {
    case light
    case dark
    case system
}

enum AppTextSize: String, CaseIterable {
    case pt12
    case pt14
    case pt16
    case pt18
    case pt20
    case pt21
    case pt22
    case pt24

    /// Base body text point size for this stop.
    var bodyPointSize: CGFloat {
        switch self {
        case .pt12: return 12
        case .pt14: return 14
        case .pt16: return 16
        case .pt18: return 18
        case .pt20: return 20
        case .pt21: return 21
        case .pt22: return 22
        case .pt24: return 24
        }
    }

    var label: String { "\(Int(bodyPointSize))pt" }

    var previous: AppTextSize? {
        let all = AppTextSize.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }

    var next: AppTextSize? {
        let all = AppTextSize.allCases
        guard let idx = all.firstIndex(of: self), idx < all.count - 1 else { return nil }
        return all[idx + 1]
    }

}

// MARK: - Line Spacing preference

enum AppSpacing: String, CaseIterable {
    case tight     // 100 %
    case snug      // 110 %
    case compact   // 120 %
    case cozy      // 130 %
    case balanced  // 140 %
    case normal    // 150 % — default
    case relaxed   // 160 %
    case loose     // 170 %
    case airy      // 180 %

    /// Additional points added above each line of body text (for 20 pt font).
    var bodyLineSpacing: CGFloat {
        switch self {
        case .tight:    return 0
        case .snug:     return 2
        case .compact:  return 4
        case .cozy:     return 6
        case .balanced: return 8
        case .normal:   return 10
        case .relaxed:  return 12
        case .loose:    return 14
        case .airy:     return 16
        }
    }

    var label: String {
        switch self {
        case .tight:    return "100%"
        case .snug:     return "110%"
        case .compact:  return "120%"
        case .cozy:     return "130%"
        case .balanced: return "140%"
        case .normal:   return "150%"
        case .relaxed:  return "160%"
        case .loose:    return "170%"
        case .airy:     return "180%"
        }
    }

    var previous: AppSpacing? {
        let all = AppSpacing.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }

    var next: AppSpacing? {
        let all = AppSpacing.allCases
        guard let idx = all.firstIndex(of: self), idx < all.count - 1 else { return nil }
        return all[idx + 1]
    }
}

// MARK: - Environment Keys

struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .purba
}

struct ModeKey: EnvironmentKey {
    static let defaultValue: AppMode = .day
}

struct TextSizeKey: EnvironmentKey {
    static let defaultValue: AppTextSize = .pt20
}

struct SpacingKey: EnvironmentKey {
    static let defaultValue: AppSpacing = .normal
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
    var appMode: AppMode {
        get { self[ModeKey.self] }
        set { self[ModeKey.self] = newValue }
    }
    var appTextSize: AppTextSize {
        get { self[TextSizeKey.self] }
        set { self[TextSizeKey.self] = newValue }
    }
    var appSpacing: AppSpacing {
        get { self[SpacingKey.self] }
        set { self[SpacingKey.self] = newValue }
    }
}

// MARK: - Colors

struct ThemeColors {
    let background:    Color
    let surface:       Color
    let border:        Color
    let accent:        Color
    let textPrimary:   Color
    let textSecondary: Color
}

struct Colors {
    static func theme(_ theme: AppTheme, mode: AppMode) -> ThemeColors {
        switch (theme, mode) {

        case (.purba, .day):
            return ThemeColors(
                background:    Color(hex: "#FAF9F6"),
                surface:       Color(hex: "#F0EDE8"),
                border:        Color(hex: "#E4DED6"),
                accent:        Color(hex: "#7A6848"),
                textPrimary:   Color(hex: "#1A1612"),
                textSecondary: Color(hex: "#504840")
            )
        case (.purba, .night):
            return ThemeColors(
                background:    Color(hex: "#080503"),
                surface:       Color(hex: "#110D06"),
                border:        Color(hex: "#1E1810"),
                accent:        Color(hex: "#8B6228"),
                textPrimary:   Color(hex: "#D4C4A8"),
                textSecondary: Color(hex: "#8C7860")
            )

        case (.abadi, .day):
            return ThemeColors(
                background:    Color(hex: "#F2F0EC"),
                surface:       Color(hex: "#E8E5DF"),
                border:        Color(hex: "#E0DDD6"),
                accent:        Color(hex: "#8C8A85"),
                textPrimary:   Color(hex: "#1C1C1C"),
                textSecondary: Color(hex: "#5A5855")
            )
        case (.abadi, .night):
            return ThemeColors(
                background:    Color(hex: "#060606"),
                surface:       Color(hex: "#0E0E0E"),
                border:        Color(hex: "#242422"),
                accent:        Color(hex: "#6B6A66"),
                textPrimary:   Color(hex: "#DDDBD6"),
                textSecondary: Color(hex: "#989590")
            )

        case (.kini, .day):
            return ThemeColors(
                background:    Color(hex: "#FAFAF8"),
                surface:       Color(hex: "#F0F0EE"),
                border:        Color(hex: "#EFEFED"),
                accent:        Color(hex: "#6B7B6E"),
                textPrimary:   Color(hex: "#1A1A1A"),
                textSecondary: Color(hex: "#506855")
            )
        case (.kini, .night):
            return ThemeColors(
                background:    Color(hex: "#040806"),
                surface:       Color(hex: "#0A100C"),
                border:        Color(hex: "#1E2820"),
                accent:        Color(hex: "#4A6B52"),
                textPrimary:   Color(hex: "#E0E4E0"),
                textSecondary: Color(hex: "#969C96")
            )

        case (.system, .day):
            return ThemeColors(
                background:    Color(hex: "#FFFFFF"),
                surface:       Color(hex: "#F2F2F7"),
                border:        Color(hex: "#E5E5EA"),
                accent:        Color(hex: "#007AFF"),
                textPrimary:   Color(hex: "#000000"),
                textSecondary: Color(hex: "#6C6C70")
            )
        case (.system, .night):
            return ThemeColors(
                background:    Color(hex: "#000000"),
                surface:       Color(hex: "#1C1C1E"),
                border:        Color(hex: "#38383A"),
                accent:        Color(hex: "#0A84FF"),
                textPrimary:   Color(hex: "#FFFFFF"),
                textSecondary: Color(hex: "#8E8E93")
            )
        }
    }
}

// MARK: - Semantic Colors

struct SemanticColors {
    struct Liturgical {
        static func highlight(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#F5E6C8") : Color(hex: "#3A2E14")
        }
        static func activeReading(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#E8F0EA") : Color(hex: "#142018")
        }
        static func congregation(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#EAE6F4") : Color(hex: "#1A1630")
        }
        static func rubric(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#C8403A") : Color(hex: "#A83030")
        }
    }
    struct Season {
        static func feastDay(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#C8A040") : Color(hex: "#A87828")
        }
        static func ordinaryTime(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#5A8060") : Color(hex: "#3A5840")
        }
        static func adventLent(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#6B5090") : Color(hex: "#4A3468")
        }
        static func easterChristmas(mode: AppMode) -> Color {
            mode == .day ? Color(hex: "#E8E0C8") : Color(hex: "#302C18")
        }
    }
}

// MARK: - Typography

// MARK: - Typography
//
// Type system:
//   Title (all themes)  — Valkyrie B Caps
//   Body · Ancient       — Valkyrie B
//   Body · Eterna        — Heliotrope 4 Tab
//   Body · Modern        — IBM Plex Mono
//   System / UI          — SF Pro (.system)

struct ThemeFont {

    // MARK: System / UI — SF Pro

    static func smallCaption(_ theme: AppTheme) -> Font {
        Font.system(size: 14)
    }

    static var titleMedium: Font {
        Font.system(size: 17, weight: .medium)
    }

    static var button: Font {
        Font.system(size: 14)
    }

    /// Button-Large — selected pane rows and top bar navigation labels.
    static var buttonLarge: Font {
        Font.system(size: 20, weight: .bold)
    }

    /// Button-Large-Regular — unselected pane rows (same size, regular weight).
    static var buttonLargeRegular: Font {
        Font.system(size: 20, weight: .regular)
    }

    /// Small superscript-style verse number rendered inline before verse text.
    /// Uses the same type family as body text for the active theme.
    static func verseNumber(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size: CGFloat = max(9, textSize.bodyPointSize * 0.58)
        switch theme {
        case .purba:  return Font.custom("ValkyrieBRegular", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabRegular", size: size)
        case .kini:   return Font.custom("IBMPlexMono", size: size)
        case .system: return Font.system(size: size)
        }
    }

    /// Lift verse numerals above the body baseline so they read as superscript.
    static func verseNumberBaselineOffset(_ textSize: AppTextSize = .pt20) -> CGFloat {
        textSize.bodyPointSize * 0.34
    }

    // MARK: Titles — Valkyrie B Caps (all themes)

    static func titleLarge(_ theme: AppTheme) -> Font {
        theme == .system
            ? Font.system(size: 32, weight: .bold)
            : Font.custom("ValkyrieBCapsRegular", size: 32).leading(.tight)
    }

    static func titleDefault(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        // Keep major reading/chapter titles clearly larger than body text.
        let size = min(36, textSize.bodyPointSize + 8)
        return theme == .system
            ? Font.system(size: size, weight: .semibold)
            : Font.custom("ValkyrieBCapsRegular", size: size).leading(.tight)
    }

    static func titleSmall(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size = textSize.bodyPointSize
        return theme == .system
            ? Font.system(size: size, weight: .semibold)
            : Font.custom("ValkyrieBCapsRegular", size: size).leading(.tight)
    }

    /// In-chapter section subheading always uses Valkyrie B Caps.
    static func chapterSectionHeading(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size = textSize.bodyPointSize
        return Font.custom("ValkyrieBCapsRegular", size: size)
    }

    static func caption(_ theme: AppTheme) -> Font {
        Font.system(size: 13, weight: .medium)
    }

    // MARK: Body — per theme

    static func bodyLarge(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size: CGFloat = min(28, textSize.bodyPointSize + 4)
        switch theme {
        case .purba:  return Font.custom("ValkyrieBRegular", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabRegular", size: size)
        case .kini:   return Font.custom("IBMPlexMono", size: size)
        case .system: return Font.system(size: size)
        }
    }

    static func bodyDefault(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size: CGFloat = textSize.bodyPointSize
        switch theme {
        case .purba:  return Font.custom("ValkyrieBRegular", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabRegular", size: size)
        case .kini:   return Font.custom("IBMPlexMono", size: size)
        case .system: return Font.system(size: size)
        }
    }

    static func bodySmall(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size: CGFloat = max(10, textSize.bodyPointSize - 2)
        switch theme {
        case .purba:  return Font.custom("ValkyrieBRegular", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabRegular", size: size)
        case .kini:   return Font.custom("IBMPlexMono", size: size)
        case .system: return Font.system(size: size)
        }
    }

    /// Italic body — for rubric/liturgical direction text.
    static func bodySmallItalic(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size: CGFloat = max(10, textSize.bodyPointSize - 2)
        switch theme {
        case .purba:  return Font.custom("ValkyrieBItalic", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabItalic", size: size)
        case .kini:   return Font.custom("IBMPlexMono-Italic", size: size)
        case .system: return Font.system(size: size).italic()
        }
    }

    static func bodyDefaultItalic(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size: CGFloat = textSize.bodyPointSize
        switch theme {
        case .purba:  return Font.custom("ValkyrieBItalic", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabItalic", size: size)
        case .kini:   return Font.custom("IBMPlexMono-Italic", size: size)
        case .system: return Font.system(size: size).italic()
        }
    }

    // MARK: - Left pane (sidebar)

    /// Primary line for book / daily rows — serif, slightly larger than body.
    static func sidebarRowPrimary(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size = min(26, textSize.bodyPointSize + 4)
        switch theme {
        case .purba:  return Font.custom("ValkyrieBRegular", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabRegular", size: size)
        case .kini:   return Font.custom("IBMPlexMono", size: size)
        case .system: return Font.system(size: size, weight: .regular)
        }
    }

    /// Italic subtitle (date, chapter count) under sidebar rows.
    static func sidebarRowSubtitle(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size = max(12, textSize.bodyPointSize - 6)
        switch theme {
        case .purba:  return Font.custom("ValkyrieBItalic", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabItalic", size: size)
        case .kini:   return Font.custom("IBMPlexMono-Italic", size: size)
        case .system: return Font.system(size: size).italic()
        }
    }

    /// Numerals inside sidebar date / chapter grids.
    static func sidebarGridCell(_ theme: AppTheme, _ textSize: AppTextSize = .pt20) -> Font {
        let size = max(13, textSize.bodyPointSize - 5)
        switch theme {
        case .purba:  return Font.custom("ValkyrieBRegular", size: size)
        case .abadi:  return Font.custom("Heliotrope4TabRegular", size: size)
        case .kini:   return Font.custom("IBMPlexMono", size: size)
        case .system: return Font.system(size: size, weight: .medium)
        }
    }
}

// MARK: - Asset catalog icons (Figma PDFs in Assets.xcassets)

/// Names must match image sets in `Assets.xcassets` exactly.
enum ThemeAssetIcon {
    static let palette = "paintpalette"
    static let book = "book"
    static let listBullet = "list.bullet"
    /// Full-color Pelita logo — use `.original` rendering, not template.
    static let sidebarLogo = "sidebar_logo"
}

/// Vector PDF from the asset catalog, tinted via `foregroundStyle` (template).
struct CatalogIcon: View {
    let name: String
    var length: CGFloat = 22

    var body: some View {
        Image(name)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: length, height: length)
    }
}

// MARK: - Letter Spacing

struct ThemeTracking {
    static func titleLarge(_ theme: AppTheme) -> CGFloat {
        switch theme {
        case .purba:  return 0
        case .abadi:  return -0.5
        case .kini:   return -0.5
        case .system: return 0
        }
    }
    static func caption(_ theme: AppTheme) -> CGFloat {
        switch theme {
        case .purba:  return 1.0
        case .abadi:  return 1.5
        case .kini:   return 1.5
        case .system: return 0.8
        }
    }
    static var button: CGFloat { return 0.8 }
}

// MARK: - Line Spacing

struct ThemeLineSpacing {
    static func bodyLarge(_ theme: AppTheme) -> CGFloat   { return 8 }
    static func bodyDefault(_ theme: AppTheme) -> CGFloat { return 10 }
    static func bodySmall(_ theme: AppTheme) -> CGFloat   { return 11 }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red:   Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: 1
        )
    }
}
