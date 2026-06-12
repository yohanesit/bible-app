# Data Models

All domain types used in Lectio, with field names, types, optionality, and purpose. Types are organized by layer: storage → network/bundle → domain → UI state.

---

## Storage layer

### BibleVerse
Defined in `BibleDatabase.swift`. One verse in a chapter.

```swift
struct BibleVerse: Codable {
    let v: Int        // verse number (1-based)
    let t: String     // verse text, normalized (Unicode spaces removed, duplicate gaps collapsed)
    let h: String?    // section heading to display before this verse (nil if no heading)
    let p: Bool?      // true = this verse starts a new paragraph (adds visual spacing above)
}
```

Stored in `BibleBookData`:
```swift
typealias BibleBookData = [String: [BibleVerse]]
// Key: chapter number as string ("1", "2", …)
// Value: verses for that chapter, unsorted in storage, sorted by `v` when returned
```

### BibleSeed
Internal decode-only type. Represents the `bible_seed.json` bundle file.

```swift
struct BibleSeed: Decodable {
    let version: String          // human-readable version label
    let seedVersion: Int?        // integer version; increment to force re-expansion on device
    let books: [String: BibleBookData]
    // Key: book slug ("kej", "mat", etc.)
    // Value: BibleBookData for that book
}
```

---

## Bundle / lectionary layer

### BundledDay
Defined in `BundledLectionary.swift`. Compact representation of one day's lectionary in the bundle files.

```swift
struct BundledDay: Codable {
    let s: String          // season raw string (e.g. "Eastertide", "Advent")
    let r: [String?]       // fixed-length 4-element array:
                           //   r[0] = first reading citation (e.g. "Acts 4:13-21")
                           //   r[1] = responsorial psalm citation
                           //   r[2] = second reading citation (nil on ferias/weekdays)
                           //   r[3] = gospel citation
    let celebration: String?  // optional override for celebration name
}
```

### LectionaryBundleFile
One year's bundled lectionary file (e.g., `lectionary_2026.json`).

```swift
struct LectionaryBundleFile: Codable {
    let year: Int                       // e.g. 2026
    let generatedAt: String             // ISO 8601 timestamp of when the file was generated
    let days: [String: BundledDay]      // key: "MM-DD" (e.g. "04-26")
}
```

### LectionaryOverridesFile
The `lectionary_overrides.json` bundle file. Holds regional feast day overrides.

```swift
struct LectionaryOverridesFile: Codable {
    let regions: [String: RegionInfo]
    // Key: region code ("ID", "US", "PH")
    
    let overrides: [String: [String: [String: BundledDay]]]
    // overrides[regionCode][yearString][MM-DD] → BundledDay
    // e.g. overrides["ID"]["2026"]["08-17"] → Indonesian Independence Day override
}
```

### RegionInfo
Metadata for a lectionary region entry.

```swift
struct RegionInfo: Codable {
    let name: String    // e.g. "Indonesia (KWI)"
    let flag: String    // emoji flag, e.g. "🇮🇩"
}
```

---

## Network / service layer

### LectionaryDay
Output type from both `LectionaryService` (network) and `BundledLectionaryStore` (bundle). Represents one day's readings as lightweight citations (no verse text).

```swift
struct LectionaryDay {
    let celebration: String             // e.g. "Senin, Masa Paskah"
    let season: String                  // raw season string from API (e.g. "Eastertide")
    let readings: [LectionaryReadingRef]
}
```

### LectionaryReadingRef
One reading reference within a `LectionaryDay`.

```swift
struct LectionaryReadingRef {
    let type: String      // e.g. "first_reading", "gospel", "psalm", "second_reading"
    let citation: String  // e.g. "Acts 4:13-21", "Psalm 118:1 and 14-15ab"
    let intro: String?    // always nil from network/bundle; assembled by DailyReadingProvider
}
```

---

## Domain layer

### MassReading
Defined in `MassReading.swift`. A single reading fully assembled for display — includes type, reference, intro rubric, body text, and response lines.

```swift
struct MassReading: Identifiable, Codable {
    let id: UUID
    let type: ReadingType          // e.g. .firstReading, .gospel
    let reference: String          // Indonesian reference, e.g. "Kis 2:14, 22-33"
    let introRubric: String        // e.g. "Bacaan dari Kisah Para Rasul."
    let bodyText: String           // Full joined verse text from BibleDatabase
    let responseRubric: String?    // e.g. "Demikianlah sabda Tuhan." (nil for gospel on some days)
    let congregationResponse: String?  // e.g. "Syukur kepada Allah."
}
```

### MassDay
Defined in `MassReading.swift`. All readings for one day, fully assembled.

```swift
struct MassDay: Codable {
    let date: Date
    let celebrationName: String     // e.g. "Senin Dalam Oktaf Paskah"
    let season: LiturgicalSeason    // e.g. .easter
    let readings: [MassReading]     // ordered by ReadingType
}
```

### ReadingType
Enum whose raw value is the Indonesian display label used directly in the UI.

```swift
enum ReadingType: String, Codable {
    case firstReading  = "BACAAN 1"
    case psalm         = "MAZMUR TANGGAPAN"
    case secondReading = "BACAAN 2"
    case gospel        = "BACAAN INJIL"
    case alleluia      = "BAIT PENGANTAR INJIL"
}
```

### LiturgicalSeason
```swift
enum LiturgicalSeason: String, Codable {
    case ordinaryTime = "ordinary_time"
    case advent       = "advent"
    case lent         = "lent"
    case easter       = "easter"
    case christmas    = "christmas"
    case feastDay     = "feast_day"
}
```

---

## Reference parsing layer

### ParsedReference
Defined in `ReferenceParser.swift`. The structured result of parsing a scripture citation like "Acts 5:27-33".

```swift
struct ParsedReference {
    let bookName: String              // e.g. "Acts" (English, from API)
    let chapter: Int                  // e.g. 5
    let verseRanges: [ClosedRange<Int>]  // e.g. [27...33]
    // Multi-range: "Acts 2:14, 22-33" → [14...14, 22...33]
}
```

### ResponsorialParsed
Used for responsorial psalms, which have a refrain and multiple strophe groups.

```swift
struct ResponsorialParsed {
    let bookName: String
    let chapter: Int
    let refrainRanges: [ClosedRange<Int>]    // verse range for the refrain (shown between strophes)
    let stropheGroups: [[ClosedRange<Int>]]  // each group is a set of verse ranges for one strophe
}
```

Example: "Psalm 118:1 and 14-15ab, 16-18, 19-21" parses as:
- `refrainRanges`: [1...1]
- `stropheGroups`: [[14...15], [16...18], [19...21]]

---

## Book catalog layer

### BookInfo
Defined in `BookNameMapper.swift`. Metadata for one Bible book used during reading assembly.

```swift
struct BookInfo {
    let englishName: String          // "Genesis", "Acts", "1 Corinthians" (API form)
    let indonesianName: String       // "Kejadian", "Kisah Para Rasul", "1 Korintus"
    let slug: String                 // "kej", "kis", "1kor" (matches BibleDatabase keys)
    let introRubric: String          // "Bacaan dari Kitab Kejadian." (pre-translated)
    let isGospel: Bool               // true for Matthew, Mark, Luke, John
    let isDeuterocanonical: Bool     // true for the 7 Deuterocanonical books
}
```

### BibleBookEntry
Defined in `BibleCatalog.swift`. Catalog record for a book — used for navigation UI.

```swift
struct BibleBookEntry: Identifiable {
    let slug: String           // "mat", "kej", "why"
    let name: String           // Indonesian name: "Matius", "Kejadian", "Wahyu"
    let section: BibleSection  // .oldTestament, .deuterocanonical, .newTestament
    let chapterCount: Int      // total chapters: 28, 50, 22
    var id: String { slug }
}
```

### BibleSection
```swift
enum BibleSection: String {
    case oldTestament      // "Perjanjian Lama"
    case deuterocanonical  // "Deuterokanonika"
    case newTestament      // "Perjanjian Baru"
}
```

---

## Theme layer

All defined in `Theme.swift`.

### AppTheme
```swift
enum AppTheme: String, CaseIterable {
    case purba   // "Klasik" — Valkyrie B, warm palette
    case abadi   // "Roman" — Heliotrope 4 Tab, neutral palette
    case kini    // "Modern" — IBM Plex Mono, minimal palette
    case system  // SF Pro, follows iOS appearance
}
```

### AppMode
Resolved from `AppColorScheme` + device color scheme.
```swift
enum AppMode { case day, night }
```

### AppColorScheme
Stored in `UserDefaults("appColorScheme")`.
```swift
enum AppColorScheme: String {
    case light, dark, system
}
```

### AppTextSize
8 stops, stored in `UserDefaults("appTextSize")`.
```swift
enum AppTextSize: String, CaseIterable {
    case pt12, pt14, pt16, pt18, pt20, pt21, pt22, pt24
    var bodyPointSize: CGFloat { ... }  // returns the CGFloat for that stop
}
```
Default: `.pt20` (20 pt).

### AppSpacing
9 stops, stored in `UserDefaults("appSpacing")`.
```swift
enum AppSpacing: String, CaseIterable {
    case tight, snug, compact, cozy, balanced, normal, relaxed, loose, airy
    var additionalLineSpacing: CGFloat { ... }  // extra points above each line
}
```
Default: `.normal` (~10 pt extra / 150% at 20 pt body size).

### ThemeColors
Produced by `Colors.theme(_ theme: AppTheme, mode: AppMode) -> ThemeColors`.
```swift
struct ThemeColors {
    let background: Color       // main page background
    let surface: Color          // cards, sheets, overlays
    let border: Color           // dividers, separators
    let accent: Color           // verse numbers, selected items, decorative elements
    let textPrimary: Color      // body reading text
    let textSecondary: Color    // labels, captions
    let rubric: Color           // intro/response rubric text
    let congregationResponse: Color  // congregation response lines
}
```

---

## UI state layer

### DayLoadState
Drives `DailyMassView`. Defined in `DailyReadingProvider.swift`.

```swift
enum DayLoadState {
    case idle
    case loading
    case loaded(MassDay)
    case needsSync(MassDay)   // data loaded but Bible text missing for ≥1 reading
    case offline(MassDay)     // loaded from cache/bundle without network confirmation
    case error(String)        // unrecoverable failure; string is user-visible message
}
```

### ChapterLoadState
Drives `BibleChapterView`. Defined in `BibleChapterProvider.swift`.

```swift
enum ChapterLoadState {
    case idle
    case loaded(bookName: String, chapter: Int, verses: [BibleVerse])
    case empty(bookName: String, chapter: Int)  // book not in local DB; sync needed
}
```
