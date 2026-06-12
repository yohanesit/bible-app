# File Structure

## Xcode project layout

```
Bible App/
├── BibleApp-Claude/           ← companion repo (scripts, tools, this docs folder)
│   ├── docs/
│   ├── scripts/
│   └── enrich_headings.py
└── BibleApp/                  ← Xcode project
    ├── BibleApp.xcodeproj/
    └── BibleApp/              ← Swift source + resources
        ├── BibleAppApp.swift
        ├── ContentView.swift
        ├── ... (25 Swift files total)
        ├── Fonts/
        │   ├── Valkyrie B Caps Bold.otf
        │   ├── Valkyrie B Caps Regular.otf
        │   └── ... (other licensed font files)
        ├── Assets.xcassets/
        │   ├── AppIcon.appiconset/
        │   ├── AccentColor.colorset/
        │   ├── sidebar_logo.imageset/
        │   └── ... (custom icons)
        ├── Info.plist
        └── PrivacyInfo.xcprivacy
```

---

## Source file reference

25 Swift files in `BibleApp/BibleApp/`:

| File | Category | Responsibility |
|---|---|---|
| `BibleAppApp.swift` | App entry | `@main`; launches background lectionary prefetch on startup |
| `ContentView.swift` | Root UI | Multi-pane layout, gesture system, navigation state, theme/preference injection |
| `LeftPaneView.swift` | Navigation | Sidebar: Lectionary accordion + date grid, 73 Bible books accordion + chapter grid, settings gear button |
| `RightPaneView.swift` | Navigation | Secondary pane (date/chapter list); currently merged into LeftPaneView behavior |
| `DailyMassView.swift` | Feature view | Renders daily Mass readings; scroll-triggered reading mode; status banners |
| `BibleChapterView.swift` | Feature view | Renders a single Bible chapter; inline verse numbers, section headings, paragraph breaks |
| `PreferencesView.swift` | Settings | Bottom sheet: theme type selector, day/night cycle button, font size stepper, line spacing stepper |
| `AdminView.swift` | Settings | Bible sync panel: source selector, API key input, sync trigger + progress, error display |
| `AcknowledgementsView.swift` | Settings | Settings sheet root: region picker, Bible version label, acknowledgements, Data & Sync link |
| `DailyPaneCalendar.swift` | Utility | Computes the 10-day date window; converts between date labels and `Date` values |
| `DailyReadingProvider.swift` | Provider | `@Observable`; orchestrates lectionary fetch → verse text lookup → `MassDay` assembly; owns `DayLoadState` |
| `BibleChapterProvider.swift` | Provider | `@Observable`; loads a single chapter from `BibleDatabase`; owns `ChapterLoadState` |
| `BibleDatabase.swift` | Data | Singleton; reads/writes book JSON files on-device; memory cache; seed expansion on first launch |
| `BibleSyncService.swift` | Data | `@Observable`; downloads full TB from alkitab.or.id API chapter-by-chapter; writes to `BibleDatabase` |
| `BibleCatalog.swift` | Data | Static registry of all 73 Catholic books: slug, Indonesian name, section, chapter count |
| `BibleSource.swift` | Data | Enum for active Bible translation (`alkitab` = TB); determines on-disk storage directory |
| `LectionaryService.swift` | Network | Fetches daily readings from cpbjr API; caches to disk; prefetches current + next year on launch |
| `BundledLectionaryStore.swift` | Bundle | Lazily loads year JSON files from bundle; resolves regional overrides; provides `LectionaryDay` |
| `BundledLectionary.swift` | Models | `Decodable` types for bundle files: `BundledDay`, `LectionaryBundleFile`, `LectionaryOverridesFile`, `RegionInfo` |
| `MassReading.swift` | Models | Core domain types: `MassDay`, `MassReading`, `ReadingType`, `LiturgicalSeason` |
| `BookNameMapper.swift` | Utility | Maps English book names (from API) → `BookInfo` (Indonesian name, slug, intro rubric, metadata) |
| `ReferenceParser.swift` | Utility | Parses citation strings ("Acts 5:27-33") → `ParsedReference` / `ResponsorialParsed` |
| `Theme.swift` | Design system | All theme enums (`AppTheme`, `AppMode`, `AppTextSize`, `AppSpacing`), `ThemeColors`, `ThemeFont`, color palettes |
| `LagumisaSlugDeriver.swift` | Utility | Maps celebration name + date → lagumisa.web.id slug for sung psalm refrain lookup |
| `LagumisaRefrainStore.swift` | Bundle | Loads `lagumisa_refrains.json` from bundle; provides slug → refrain text lookup |

---

## Bundle resources

Files included in the app bundle (shipped with every install):

| File | Size (approx.) | Purpose |
|---|---|---|
| `bible_seed.json` | ~5–8 MB uncompressed | Full TB Bible text for all 73 books; expanded to on-device files on first launch |
| `lectionary_2026.json` | ~44 KB | Bundled lectionary for year 2026 |
| `lectionary_2027.json` | ~44 KB | Bundled lectionary for year 2027 |
| `lectionary_2028.json` | ~44 KB | Bundled lectionary for year 2028 |
| `lectionary_2029.json` | ~44 KB | Bundled lectionary for year 2029 |
| `lectionary_2030.json` | ~44 KB | Bundled lectionary for year 2030 |
| `lectionary_overrides.json` | ~5–10 KB | Regional feast day overrides (ID, US, PH) |
| `lagumisa_refrains.json` | ~50–100 KB | Sung responsorial psalm refrains, keyed by lagumisa slug |
| `Valkyrie B Caps Bold.otf` | — | Title font (Purba, Abadi, Kini themes) |
| `Valkyrie B Caps Regular.otf` | — | Title font variant |
| `Heliotrope 4 Tab *.otf` | — | Body font for Abadi theme |
| `IBM Plex Mono *.otf` | — | Body font for Kini theme |
| Other `.otf` files | — | Additional licensed fonts (some may be legacy/unused) |

All font files must be registered in `Info.plist` under the `UIAppFonts` key.

---

## On-device storage layout

Files written by the app at runtime:

```
~/Documents/
└── bible/
    └── tb/
        ├── .seeded          ← sentinel: presence means seed has been expanded for this source
        ├── kej.json         ← Genesis (BibleBookData: { "1": [BibleVerse], "2": [...], ... })
        ├── kel.json         ← Exodus
        ├── im.json          ← Leviticus
        ├── bil.json         ← Numbers
        ├── ul.json          ← Deuteronomy
        ├── ...              ← one file per book slug (up to 73 files)
        └── why.json         ← Revelation

~/Library/Caches/
└── lectionary/
    ├── 2026/
    │   ├── 01-01.json      ← cached cpbjr API response for Jan 1, 2026
    │   ├── 01-02.json
    │   └── ...             ← one file per day
    └── 2027/
        └── ...
```

### UserDefaults keys

| Key | Type | Default | Purpose |
|---|---|---|---|
| `appTheme` | String | `"purba"` | Active theme (purba/abadi/kini/system) |
| `appColorScheme` | String | `"light"` | Day/night preference (light/dark/system) |
| `appTextSize` | String | `"pt20"` | Body font size stop |
| `appSpacing` | String | `"normal"` | Line spacing stop |
| `bibleSource` | String | `"alkitab"` | Active Bible source/translation |
| `lectionaryRegion` | String | `"ID"` | Lectionary region code |
| `alkitabApiKey` | String | `""` | alkitab.or.id API key (admin sync) |
| `lastBibleSync` | Date | nil | Timestamp of last completed Bible sync |
| `bibleSeedBundleRevision` | Int | 0 | Tracks which seed version is on-device; compared to bundle's `seedVersion` |

---

## Scripts

In `BibleApp-Claude/scripts/`:

| File | Language | Purpose |
|---|---|---|
| `generate_lectionary_bundle.py` | Python | Fetches cpbjr API + imankatolik.or.id day names; outputs `lectionary_YYYY.json` files |
| `scrape_lagumisa.py` | Python | Scrapes lagumisa.web.id for Sunday/feast sung psalm refrains; outputs `lagumisa_refrains.json` |
| `scrape_imankatolik.py` | Python | Scrapes imankatolik.or.id for Indonesian liturgical celebration names |
| `clean_tb_seed.py` | Python | Cleans and normalizes raw TB Bible text (Unicode normalization, whitespace); outputs seed-ready JSON |
| `clean_refrains.py` | Python | Post-processes raw scraped refrain text |
| `ocr_refren.swift` | Swift | OCR utility for extracting refrain text from scanned liturgical images (not in app target) |
| `enrich_headings.py` | Python | (root of BibleApp-Claude) Enriches verse data with section headings |

These scripts are used to generate and update the bundle resources. They are not part of the app build target.
