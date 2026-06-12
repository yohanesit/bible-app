# BibleApp (MVP)

Open `BibleApp.xcodeproj` in Xcode, select a simulator (e.g. iPhone 17), Run.

## Features

- **Daily readings** placeholder + **Bible** text from bundled JSON (`Resources/BibleData/`, flat `bookId_chapter.json`).
- **Swipe** left: book list + Bacaan Harian; swipe right: dates (daily) or verse index (Bible chapter).
- **Reader settings**: theme (light / sepia / dark), text size S/M/L (fixed scale tiers; see `ReaderSizing.swift`).
- **Highlights & notes**: long-press a verse → highlight color or note; **Tersimpan** lists items; **SwiftData** (local store on simulator).
- Typography/colors follow Figma tokens in code (`AppTypography`, `AppColors`); add licensed font files + **Info.plist** font entries when ready.

## Run destination

This target is **simulator-only** (`SUPPORTED_PLATFORMS = iphonesimulator`). Pick any **iPhone Simulator** in the scheme destination menu. Highlights/notes use **local SwiftData** only (no iCloud).

## Signing

Simulator builds typically need no device provisioning. If you later re-enable a **device** build, add your Development Team and consider restoring iCloud if you want CloudKit sync again.
