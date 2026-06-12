# Extending the App

Concrete recipes for the most common extension scenarios. Each recipe lists every file that needs to change and why.

---

## 1. Add a new lectionary region

No Swift code changes required.

**Steps:**

1. Open `BibleApp/BibleApp/lectionary_overrides.json` (the bundle file, not on-device).

2. Add a new entry in `"regions"`:
   ```json
   "AU": { "name": "Australia (ACBC)", "flag": "🇦🇺" }
   ```

3. Add override entries for that region's feast days in `"overrides"`:
   ```json
   "overrides": {
     "AU": {
       "2026": {
         "01-26": {
           "s": "OrdinaryTime",
           "r": ["Acts 13:16-17, 22-25", "Psalm 89:2-3, 21-22, 25, 27", null, "Matthew 2:1-12"],
           "celebration": "Australia Day (Our Lady Help of Christians)"
         }
       }
     }
   }
   ```

4. Replace `lectionary_overrides.json` in the Xcode project (drag-and-drop to replace in the bundle).

`BundledLectionaryStore.availableRegions` and the Settings region picker read all keys from the `"regions"` object automatically. No Swift changes needed.

---

## 2. Add a new Bible translation/source

**Files to change:**

- `BibleSource.swift` — add a new case
- `BibleDatabase.swift` — no changes needed; it reads `storageDirName` from `BibleSource` automatically
- `BibleSyncService.swift` (or create a parallel service) — add sync logic for the new API
- `AdminView.swift` — add a source section for the new translation
- Optional: add a new seed JSON file and update `expandSeedIfNeeded` in `BibleDatabase.swift`

**Step 1 — BibleSource.swift:**
```swift
enum BibleSource: String, CaseIterable {
    case alkitab   // TB
    case bis       // Bahasa Indonesia Sehari-hari (example)

    var storageDirName: String {
        switch self {
        case .alkitab: return "tb"
        case .bis: return "bis"
        }
    }
}
```

**Step 2 — BibleDatabase:** No changes. `BibleDatabase` constructs the path from `source.storageDirName`. The new directory is created automatically on first access.

**Step 3 — Sync service:** Either extend `BibleSyncService` with a `bis` sync path, or create `BISSyncService` following the same `@Observable` pattern with its own `baseURL` and chapter count manifest.

**Step 4 — AdminView:** Add a section showing book count for `.bis` and a sync trigger for the new service.

---

## 3. Add a new theme

**Files to change:**

- `Theme.swift` — add enum case, color palette, font selections
- `PreferencesView.swift` — add a theme card to the picker
- `Info.plist` — register any new font files under `UIAppFonts`

**Step 1 — Theme.swift, AppTheme enum:**
```swift
enum AppTheme: String, CaseIterable {
    case purba, abadi, kini, system
    case nova   // ← new theme
}
```

**Step 2 — Theme.swift, Colors.theme:**
```swift
case (.nova, .day):
    return ThemeColors(
        background: Color(red: 0.96, green: 0.97, blue: 0.99),
        surface: Color(red: 0.92, green: 0.94, blue: 0.97),
        // ... all required fields
    )
case (.nova, .night):
    return ThemeColors( ... )
```

**Step 3 — Theme.swift, ThemeFont:** Add a `case .nova:` branch to every switch in `ThemeFont` (body, title, verseNumber, UI, etc.). This is the most labor-intensive step — search for `switch theme` in `Theme.swift` to find all locations.

**Step 4 — PreferencesView.swift:** Add the new theme to the card row. The picker currently filters `.allCases` to exclude `.system` from the card display — the new theme should appear in the list.

**Step 5 — Info.plist:** If the new theme uses a custom font file not already registered, add the filename to the `UIAppFonts` array.

---

## 4. Add a new lectionary year bundle

Run when the bundled years (currently 2026–2030) need to be extended.

**Steps:**

1. Run the generation script from `BibleApp-Claude/`:
   ```bash
   python3 scripts/generate_lectionary_bundle.py --year 2031
   ```
   This fetches cpbjr API data + imankatolik.or.id day names and outputs `lectionary_2031.json`.

2. Add `lectionary_2031.json` to the Xcode project:
   - Drag the file into `BibleApp/BibleApp/` in Xcode
   - Ensure "Add to target: BibleApp" is checked (Copy Bundle Resources)

3. No Swift code changes needed. `BundledLectionaryStore.loadYear(_:)` constructs the filename as `"lectionary_\(year)"` and calls `Bundle.main.url(forResource:withExtension:)`. Any year file in the bundle is found automatically.

---

## 5. Add a new reading type

**Files to change:**

- `MassReading.swift` — add case to `ReadingType`
- `BookNameMapper.swift` — map the API type string to the new case
- `DailyReadingProvider.swift` — add rubric/response assembly for the new type
- `DailyMassView.swift` / `ReadingView` — update rendering if the type needs different layout

**Step 1 — MassReading.swift:**
```swift
enum ReadingType: String, Codable {
    // existing cases...
    case sequence = "SEKUENSI"   // ← example: liturgical sequence
}
```
The raw value is used directly as the display label in the UI.

**Step 2 — BookNameMapper.swift, `readingType(from:)` function:**
```swift
case "sequence", "sequentia": return .sequence
```

**Step 3 — DailyReadingProvider.swift:** In the assembly loop, add a branch for the new `ReadingType` to set `responseRubric` and `congregationResponse` as appropriate.

**Step 4 — DailyMassView.swift:** If the new type requires a visually distinct layout (different indentation, a different font, a border, etc.), add a case to the `ReadingView` switch on `reading.type`.

---

## 6. Update bible_seed.json

The seed file bundles all 73 books of TB text. Update it when the source text is corrected or enriched (e.g., adding section headings via `enrich_headings.py`).

**Steps:**

1. Generate or obtain the new seed JSON (output of `clean_tb_seed.py` or `enrich_headings.py`).

2. **Increment `seedVersion`** in the JSON root:
   ```json
   { "version": "2.1.0", "seedVersion": 3, "books": { ... } }
   ```
   This integer is compared to `UserDefaults("bibleSeedBundleRevision")` on every launch. If the bundle's value is higher, all book files are overwritten.

3. Replace `bible_seed.json` in the Xcode project (ensure it is in Copy Bundle Resources).

4. On the next app launch, `BibleDatabase.expandSeedIfNeeded()` detects the version bump and overwrites all on-device book files from the new seed. This is transparent to the user.

---

## 7. Feature flags

There is no feature flag system today.

**For user-visible toggles** (features the user can turn on/off): add an `@AppStorage` boolean key. Follow the naming convention of existing keys.

**For developer-only features**: use `#if DEBUG` blocks.

**Recommendation before adding multiple conditional features**: create a central `FeatureFlags` enum:
```swift
enum FeatureFlags {
    static var enableBookmarks: Bool {
        UserDefaults.standard.bool(forKey: "ff_bookmarks")
    }
}
```
This avoids scattering raw `UserDefaults` key strings across the codebase.

---

## 8. First tests to write

There are currently no unit tests. The highest-value tests to add, in priority order:

| Target | Why |
|---|---|
| `ReferenceParser` | Pure functions with complex edge cases (multi-range citations, verse letter suffixes like "15ab", psalm refrain parsing). No dependencies — trivially testable. |
| `LagumisaSlugDeriver.liturgicalCycle(for:)` | Year boundary logic (liturgical year starts on the first Sunday of Advent, not January 1). Easy to get wrong; hard to spot visually. |
| `BundledLectionaryStore.day(for:region:)` | Tests the override resolution priority: region override > base year > nil. Mock the bundle files with in-memory JSON. |
| `DailyReadingProvider` state transitions | Mock `LectionaryService` and `BibleDatabase` to test: idle → loading → loaded, loaded → needsSync, network failure → offline. |

Add tests in a new `BibleAppTests` target in the Xcode project. Use `XCTest`. No third-party testing frameworks needed.
