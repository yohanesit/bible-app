# Code Conventions

Patterns used throughout the codebase that a new engineer must know to write idiomatic code. Following these prevents bugs and keeps the codebase coherent.

---

## 1. Singleton services vs. injectable providers

**Rule**: Stateless services are singletons accessed via `.shared`. Stateful data providers are `@Observable` objects instantiated in `ContentView` and injected via `@Environment`.

| Type | Pattern | Examples |
|---|---|---|
| Stateless service / store | `TypeName.shared` | `BibleDatabase.shared`, `LectionaryService.shared`, `BundledLectionaryStore.shared`, `LagumisaRefrainStore.shared` |
| Stateful provider | `@State private var x = Provider()` in `ContentView`, then `.environment(x)` | `DailyReadingProvider`, `BibleChapterProvider` |

In a view, read a provider with:
```swift
@Environment(DailyReadingProvider.self) private var readingProvider
```

Never instantiate a provider inside a view (it would be recreated on every re-render). Never call a singleton's `init()` — always use `.shared`.

---

## 2. Theme propagation via environment — never via parameters

**Rule**: All theme values (`AppTheme`, `AppMode`, `AppTextSize`, `AppSpacing`) must be read from `@Environment`, not passed as explicit parameters.

```swift
// Correct
@Environment(\.appTheme) private var theme
@Environment(\.appMode) private var mode
let colors = Colors.theme(theme, mode: mode)

// Wrong — don't do this
struct ReadingView: View {
    let theme: AppTheme  // ← never pass theme as a parameter
    ...
}
```

`ContentView` sets these environment values once from `@AppStorage`. Any view in the hierarchy can read them without threading them through intermediate views.

---

## 3. Font access — always use ThemeFont

**Rule**: Never call `Font.custom(...)` or `Font.system(...)` directly in a view. Use `ThemeFont.*` static methods.

```swift
// Correct
Text(verse.t)
    .font(ThemeFont.body(theme, size: textSize))

// Wrong
Text(verse.t)
    .font(.custom("ValkyrieBCaps-Regular", size: 20))  // ← bypasses theme
```

`ThemeFont` switches on `AppTheme` and selects the correct font family, weight, and size. This is the only place where font names are hardcoded.

---

## 4. Color access — always use Colors.theme

**Rule**: Never use `Color(red:green:blue:)` or `Color(hex:)` directly in a view. Always get colors from `Colors.theme(_:mode:)`.

```swift
// Correct
let colors = Colors.theme(theme, mode: mode)
Text(reading.reference)
    .foregroundStyle(colors.textSecondary)

// Wrong
Text(reading.reference)
    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))  // ← breaks theming
```

---

## 5. Async pattern — async/await with MainActor, no Combine

**Rule**: All asynchronous work uses `async/await` and `Task { }`. UI state updates use `await MainActor.run { }`. Do not introduce Combine publishers.

```swift
// Correct
func loadDay(_ date: Date) {
    Task {
        let day = try await LectionaryService.shared.fetchDay(date)
        await MainActor.run {
            self.state = .loaded(day)
        }
    }
}

// Wrong — do not use Combine
let publisher = PassthroughSubject<MassDay, Never>()  // ← not used in this codebase
```

---

## 6. UserDefaults key names

All `@AppStorage` keys must match exactly. There is no central constants file — the key string appears in both the `@AppStorage` declaration and in any `UserDefaults.standard` call elsewhere.

| Key | Type | Location |
|---|---|---|
| `"appTheme"` | String | `ContentView.swift` |
| `"appColorScheme"` | String | `ContentView.swift` |
| `"appTextSize"` | String | `ContentView.swift` |
| `"appSpacing"` | String | `ContentView.swift` |
| `"bibleSource"` | String | `ContentView.swift`, `BibleDatabase.swift` (via `bibleSourceKey`) |
| `"lectionaryRegion"` | String | `ContentView.swift`, `AcknowledgementsView.swift`, `DailyReadingProvider.swift` |
| `"alkitabApiKey"` | String | `BibleSyncService.swift` |
| `"lastBibleSync"` | Date | `BibleSyncService.swift` |
| `"bibleSeedBundleRevision"` | Int | `BibleDatabase.swift` (via `seedBundleRevisionKey`) |

If a key is renamed, update every occurrence. Consider extracting to a shared constants enum if the list grows.

---

## 7. Book slugs and naming conventions

**Rule**: Book slugs are lowercase abbreviations matching alkitab.or.id conventions. Never hardcode a book name in a view — always go through `BibleCatalog` or `BookNameMapper`.

Examples of correct slugs: `"kej"` (Genesis), `"1kor"` (1 Corinthians), `"why"` (Revelation), `"mat"` (Matthew), `"kis"` (Acts).

```swift
// Correct: get name from catalog
BibleCatalog.entry(forSlug: "mat")?.name  // → "Matius"

// Wrong: hardcode names
Text("Matius")  // ← breaks if names change or localization is added
```

---

## 8. UI strings are Indonesian — no localization framework

**Rule**: All user-visible strings are hardcoded in Indonesian in the source. There is no `.strings` file, no `NSLocalizedString`, and no localization framework. Code identifiers and inline comments are English.

When adding a new user-visible string, write the Indonesian text directly as a string literal. If the app expands to support multiple UI languages in the future, this is the point where a localization pass would be needed.

---

## 9. Error handling patterns by layer

| Layer | Pattern |
|---|---|
| `LectionaryService` | Throws typed `LectionaryServiceError` (`.notFound`, `.decodingError`, `.networkError`) |
| `BibleSyncService` | Sets `error: String?` on the `@Observable` object; does not throw |
| `BibleDatabase` (reads) | Uses `try?` silently for cache reads; returns `nil` on failure |
| `BibleDatabase` (writes) | Throws on JSON encoding or file write failure |
| View layer | Reads state enums (`DayLoadState`, `ChapterLoadState`); never catches errors directly |

Views should never call `try` directly. All error handling happens in providers and services before the state is set.

---

## 10. File organization within a Swift file

Each file has a single primary type. Use `// MARK: -` comments to separate logical sections. Preview structs go at the bottom.

```swift
// MARK: - Models
struct MassReading { ... }

// MARK: - Provider
@Observable final class DailyReadingProvider {
    // MARK: State
    var state: DayLoadState = .idle

    // MARK: Public interface
    func loadDay(_ date: Date) { ... }

    // MARK: Private
    private func assemble(...) { ... }
}

// MARK: - Preview
#Preview { DailyMassView() }
```

---

## 11. Synchronous local reads are acceptable

**Rule**: `BibleDatabase.verses()` and `BibleDatabase.passage()` are synchronous. Callers should not wrap them in `Task { }` or `DispatchQueue.global().async { }` unless there is a demonstrated performance problem.

Local file reads on iOS from the app's Documents directory at the sizes used here (50–200 KB per book) complete in < 5ms. The in-memory cache eliminates disk I/O for repeated reads entirely. Making these async would add `await` noise throughout every call site for no benefit.
