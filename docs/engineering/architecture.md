# Architecture

## System overview

Lectio is a fully local iOS app. All data lives on-device; the network is used only for optional incremental updates. The architecture is layered:

```
┌──────────────────────────────────────────────────────────┐
│                        SwiftUI Views                      │
│   ContentView  DailyMassView  BibleChapterView            │
│   LeftPaneView  PreferencesView  AdminView                │
│   AcknowledgementsView  RightPaneView                     │
└────────────┬──────────────────────┬──────────────────────┘
             │ @Environment         │ @Environment
┌────────────▼────────────┐  ┌──────▼──────────────────────┐
│  DailyReadingProvider   │  │   BibleChapterProvider       │
│  (@Observable, @State   │  │   (@Observable, @State       │
│   in ContentView)       │  │    in ContentView)           │
└────────────┬────────────┘  └──────┬──────────────────────┘
             │                      │
┌────────────▼────────────┐  ┌──────▼──────────────────────┐
│ BundledLectionaryStore  │  │      BibleDatabase           │
│ LectionaryService       │  │      (shared singleton)      │
│ (singletons)            │  │                              │
└────────────┬────────────┘  └──────┬──────────────────────┘
             │                      │
┌────────────▼────────────┐  ┌──────▼──────────────────────┐
│   Bundle JSON files     │  │   Documents/bible/tb/*.json  │
│   Library/Caches/       │  │   (on-device files)          │
│   (disk cache)          │  │                              │
└────────────┬────────────┘  └──────┬──────────────────────┘
             │                      │
       cpbjr GitHub Pages    alkitab.or.id API
       (lectionary API)      (Bible sync API)
```

Supporting singletons used by both providers:
- `BookNameMapper` — English→Indonesian book name resolution
- `ReferenceParser` — citation string → structured ranges
- `LagumisaRefrainStore` — slug→refrain in-memory map
- `LagumisaSlugDeriver` — date/celebration → Lagumisa slug
- `BibleCatalog` — authoritative 73-book registry

---

## State management

### Providers
Two `@Observable` providers own all reading state. They are created once as `@State` in `ContentView` and injected into the entire view hierarchy via `@Environment`:

```swift
// ContentView.swift
@State private var readingProvider = DailyReadingProvider()
@State private var chapterProvider = BibleChapterProvider()

var body: some View {
    ...
    .environment(readingProvider)
    .environment(chapterProvider)
}
```

Views read them with:
```swift
@Environment(DailyReadingProvider.self) private var readingProvider
@Environment(BibleChapterProvider.self) private var chapterProvider
```

### Singletons
Stateless services (databases, stores) are accessed via `.shared`:
- `BibleDatabase.shared`
- `BundledLectionaryStore.shared`
- `LectionaryService.shared`
- `LagumisaRefrainStore.shared`

These are not injected via environment — they are called directly from provider methods.

### Preferences
All user preferences are stored in `UserDefaults` via `@AppStorage` in `ContentView`. They are then propagated down the tree as custom `EnvironmentValues`:

```swift
// ContentView.swift
@AppStorage("appTheme") private var appThemeRaw: String = ...
// ...

var body: some View {
    content
        .environment(\.appTheme, AppTheme(rawValue: appThemeRaw) ?? .purba)
        .environment(\.appMode, resolvedMode)
        .environment(\.appTextSize, AppTextSize(rawValue: appTextSizeRaw) ?? .pt20)
        .environment(\.appSpacing, AppSpacing(rawValue: appSpacingRaw) ?? .normal)
}
```

---

## Navigation model

All navigation state lives as `@State` in `ContentView`. No navigation stack is used.

```swift
enum Pane { case left, center }
enum LeftSelection {
    case daily
    case book(slug: String)
}

@State private var activePane: Pane = .center
@State private var leftSelection: LeftSelection = .daily
@State private var selectedRightLabel: String? = nil   // date label or "N" (chapter)
```

| State | Meaning |
|---|---|
| `activePane == .left` | Left sidebar is open |
| `leftSelection == .daily` | Center view shows DailyMassView |
| `leftSelection == .book("mat")` | Center view shows BibleChapterView for Matthew |
| `selectedRightLabel == "26 April"` | Date label for today (daily mode) |
| `selectedRightLabel == "5"` | Chapter 5 selected (book mode) |

When the user taps a date in the sidebar, `selectedRightLabel` is updated and `ContentView.onChange(of: selectedRightLabel)` calls `triggerLoadForSelectedDate()` → `readingProvider.loadDay(date)`.

When the user taps a chapter, `leftSelection` is updated and `ContentView.onChange(of: leftSelection)` calls `chapterProvider.load(slug:chapter:)`.

---

## Gesture system

The pane open/close is driven by a `DragGesture` on the root `ZStack`:

1. User drags horizontally → `dragOffset` accumulates
2. `centerPaneX` (the X position of the center content surface) is computed: `panIsOpen ? leftPaneWidth + dragOffset : dragOffset`
3. The left pane applies a **parallax offset**: moves at 30% of `centerPaneX` (creating depth)
4. The left pane applies a **scale**: ranges from 0.982 (fully closed) to 1.0 (fully open)
5. On `.onEnded`: if drag exceeded 35% of `leftPaneWidth`, toggle pane state; else spring back
6. Spring animation: `response: 0.38`, `dampingFraction: 0.82`
7. **Haptic feedback**: `UIImpactFeedbackGenerator(style: .light).impactOccurred()` fires on pane open

---

## Reading mode

`isReadingState: Bool` in `ContentView` controls immersive mode:

- **Enters** when scroll offset in the reading view exceeds 2 pt (user has scrolled)
- **Exits** when scroll returns to top (offset ≤ 0), or on a tap gesture in the reading area

Effects of `isReadingState == true`:
- Bottom bar hides via `.transition(.move(edge: .bottom).combined(with: .opacity))`
- Status bar hides via `.statusBarHidden(isReadingState)`
- Both animated with `withAnimation(.easeInOut(duration: 0.2))`

---

## Theme system

Themes are resolved in `ContentView` from `@AppStorage` values and injected as environment keys:

```
@AppStorage("appTheme")       → AppTheme enum
@AppStorage("appColorScheme") → AppColorScheme enum  ─┐
                                device colorScheme    ─┴→ AppMode (.day / .night)
@AppStorage("appTextSize")    → AppTextSize enum
@AppStorage("appSpacing")     → AppSpacing enum
```

In any view:
```swift
@Environment(\.appTheme) var theme
@Environment(\.appMode) var mode
let colors = Colors.theme(theme, mode: mode)   // → ThemeColors
let bodyFont = ThemeFont.body(theme, size: textSize)  // → Font
```

`Theme.swift` is the single source of truth for all color values and font selections. No view should call `Color(red:green:blue:)` or `Font.custom(...)` directly.

---

## Daily reading data flow

Step-by-step from user action to rendered text:

```
1. User selects a date in the sidebar
         ↓
2. ContentView.triggerLoadForSelectedDate()
   → DailyReadingProvider.loadDay(date)
         ↓
3. Check in-memory cache
   Hit → return immediately
         ↓
4. BundledLectionaryStore.shared.day(for: date, region: selectedRegion)
   ├── Check overrides[region][year][MM-DD]
   ├── Check lectionary_YYYY.json[MM-DD]
   └── nil → fall through to network
         ↓
5. (If bundle miss) LectionaryService.shared.fetchDay(date)
   → GET https://cpbjr.github.io/.../readings/{YEAR}/{MM-DD}.json
   → Disk cache: Library/Caches/lectionary/{YEAR}/{MM-DD}.json
   → Fallback: read from disk cache if network unavailable
         ↓
6. For each LectionaryReadingRef in LectionaryDay.readings:
   a. BookNameMapper.info(forEnglish: citation.bookName)
      → BookInfo (slug, Indonesian name, introRubric, isGospel)
   b. ReferenceParser.parse(citation.citation)
      → ParsedReference (chapter, verseRanges)
      → ResponsorialParsed (for psalm: refrain + strophe groups)
   c. BibleDatabase.shared.verses(bookSlug: slug, chapter: chapter)
      → Check memory cache
      → Read Documents/bible/tb/{slug}.json
      → Return [BibleVerse] sorted by verse number
   d. Filter verses for the citation's ranges
   e. Assemble MassReading (intro rubric, body text, response lines)
         ↓
7. Assemble MassDay
   → DailyReadingProvider.state = .loaded(massDay)
   → (or .needsSync if any verse lookup returned nil)
         ↓
8. DailyMassView observes state via @Environment
   → Re-renders with complete reading content
```

---

## Bible chapter data flow

```
1. User taps a chapter in the sidebar
         ↓
2. ContentView.onChange(leftSelection)
   → BibleChapterProvider.load(slug: "mat", chapter: 5)
         ↓
3. BibleCatalog.entry(forSlug: "mat")
   → BibleBookEntry (name: "Matius", chapterCount: 28)
         ↓
4. BibleDatabase.shared.verses(bookSlug: "mat", chapter: 5)
   → Check memory cache ["alkitab|mat"]
   → If miss: read Documents/bible/tb/mat.json
   → Decode, sort by verse number, cache
   → Return [BibleVerse]
         ↓
5. BibleChapterProvider.state = .loaded(bookName: "Matius", chapter: 5, verses: [...])
         ↓
6. BibleChapterView renders:
   - Header: "Matius 5"
   - Accent divider
   - Verses in flow (verse number + text, headings, paragraph breaks)
```

If the JSON file does not exist → `BibleDatabase.verses()` returns `nil` → state = `.empty(bookName:chapter:)` → "Teks belum tersedia" message shown.

---

## Startup sequence

```
BibleAppApp (init)
  └─ WindowGroup { ContentView() }

ContentView.onAppear
  ├─ BibleDatabase.shared.expandSeedIfNeeded()   ← sync; runs before first render
  ├─ applyBibleSource()                          ← set BibleDatabase.source from UserDefaults
  ├─ ensureDefaultRightSelection()               ← set today's date label
  └─ triggerLoadForSelectedDate()                ← kick off first daily reading load

BibleAppApp.task (background)
  └─ LectionaryService.shared.prefetchYearIfNeeded()
     ├─ prefetch all days of current year not yet in disk cache
     └─ prefetch all days of next year not yet in disk cache
```

The seed expansion (`expandSeedIfNeeded`) is the only blocking operation on launch. It runs once on first install and again only when `seedVersion` increments in a new app version. On subsequent launches it completes in < 1ms (sentinel file check).
