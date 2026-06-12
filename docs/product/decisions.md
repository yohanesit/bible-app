# Product & Architecture Decisions

This is a living document. Each entry explains a non-obvious choice that was made, and why. Add a new entry whenever a decision is made that a future team member would otherwise question.

---

## 1. Offline-first design

**Decision**: All essential content (Bible text, lectionary) is available on-device. Network is never required for reading.

**Why**: Indonesian parishes often have unreliable WiFi. Mass starts at a fixed time; the app must work in airplane mode. Bible text is static and small enough to bundle (~5 MB compressed). The cost of a network outage is zero if the data is already on-device.

---

## 2. TB translation only (no NAB, NRSV, or other translations)

**Decision**: The app ships with one Bible translation — TB (Terjemahan Baru), the standard Indonesian Catholic Bible.

**Why**: The target audience reads Indonesian. NAB and NRSV are English translations used in other regions; adding them would double the app size, complicate the UI, and fragment the experience without serving the actual user. If a second translation is ever needed, the `BibleSource` enum is already designed to accommodate it.

---

## 3. Bundled lectionary instead of network-only

**Decision**: Five years of lectionary data (2026–2030) are bundled in the app as JSON files.

**Why**: The cpbjr API is a static GitHub Pages site with no SLA and no uptime guarantee. Bundling five years (~220 KB compressed) costs almost nothing in app size and completely eliminates dependency on a free volunteer-run server for the app's primary feature. After 2030, the app falls back gracefully to the live API.

---

## 4. Deuterocanonical books come from seed, not sync

**Decision**: The 7 Deuterocanonical books (Tobit, Judith, 1 & 2 Maccabees, Wisdom, Sirach, Baruch) are bundled in `bible_seed.json` and are never downloaded from the admin sync API.

**Why**: `bible-api.alkitab.or.id` is based on the Protestant 66-book canon and does not publish Deuterocanonical texts. The Deuterocanonical text is sourced from `imankatolik.or.id` (credited in Acknowledgements) and pre-processed into the seed bundle. A separate sync path for these 7 books would add significant complexity for a one-time, rarely-changing dataset.

---

## 5. No external dependencies (no CocoaPods, no SPM)

**Decision**: The app uses no third-party frameworks — only SwiftUI and Foundation from Apple.

**Why**: External dependencies add build complexity, supply chain risk, and update maintenance burden. SwiftUI covers all UI needs. Foundation covers JSON decoding, networking, and date handling. The app is fully auditable: every line of code is in the repo. This also means the build is reproducible without any package manager step.

---

## 6. @Observable + @Environment instead of Combine/MVVM

**Decision**: The two data providers (`DailyReadingProvider`, `BibleChapterProvider`) use the `@Observable` macro (iOS 17) and are injected into views via `@Environment`.

**Why**: `@Observable` is the idiomatic iOS 17 pattern — less boilerplate than `ObservableObject`/`@Published`, cleaner than a full MVVM setup with separate ViewModels per view, and avoids the complexity of Combine publishers. The environment injection model integrates cleanly with the multi-pane layout where a single root view owns both providers.

---

## 7. No user accounts

**Decision**: There is no login, no sync-to-cloud, and no reading history stored beyond the local device.

**Why**: Lectio is a reading tool, not a social platform. Sync is one-directional (download Bible text to device). Adding accounts would require auth infrastructure, a backend, a privacy policy covering personal data, and App Store privacy disclosures — all overhead with no user benefit for the current feature set. If bookmarking or highlighting is added in the future, iCloud document sync or CloudKit is the right path (no custom backend required).

---

## 8. Sliding sidebar pane instead of NavigationStack

**Decision**: Navigation uses a gesture-driven sliding sidebar (88% of screen width) with parallax animation, rather than a standard iOS NavigationStack with a navigation bar.

**Why**: The reading experience should feel like a book, not a settings panel. A `NavigationStack` forces a navigation bar at the top, which conflicts with the immersive reading mode and shrinks the reading area. The sliding pane lets the navigation chrome appear only when needed (on gesture) and disappear completely during reading, while the 88%-width sidebar gives the book list a typographic scale that a standard table view cannot.

---

## 9. API key in UserDefaults, not Keychain {#api-key-storage}

**Decision**: The alkitab.or.id API key is stored in `UserDefaults("alkitabApiKey")`, not the iOS Keychain.

**Why**: The admin sync panel is a developer-facing tool, not a user-facing feature. At the time this was built, the tradeoff was acceptable: the API key is not a user credential and has low-blast-radius if exposed on a personal device. If the admin panel becomes user-facing (e.g., users are expected to register and enter their own keys), this must be migrated to the Keychain using `SecItemAdd`/`SecItemCopyMatching`.

---

## 10. Synchronous local file reads in BibleDatabase

**Decision**: `BibleDatabase.verses()` and `BibleDatabase.passage()` are synchronous (not `async`), even though they read from disk.

**Why**: Each book JSON file is small (~50–200 KB) and lives in the app's Documents directory on a fast SSD. On iOS, reads from local app storage at this size complete in < 5ms. Making them `async` would require threading coordination in every call site for no practical benefit. The memory cache further ensures that repeated reads (same chapter viewed twice) never touch disk at all.
