# Lectio — App Documentation

Lectio is a Catholic liturgical reading app for Indonesian users. It provides daily Mass readings from the Roman Rite lectionary and a full-text Bible reader covering all 73 books of the Catholic canon, using the TB (Terjemahan Baru) translation. The app is built entirely offline-first: all essential content is bundled with the app and works without a network connection.

## Who should read what

| I am a... | Start here |
|---|---|
| Product Manager | [product/overview.md](product/overview.md) |
| PM — user journeys | [product/user-flows.md](product/user-flows.md) |
| PM — feature detail | [product/features.md](product/features.md) |
| PM — why decisions were made | [product/decisions.md](product/decisions.md) |
| Engineer — onboarding | [engineering/architecture.md](engineering/architecture.md) |
| Engineer — data structures | [engineering/data-models.md](engineering/data-models.md) |
| Engineer — external APIs | [engineering/apis.md](engineering/apis.md) |
| Engineer — file map | [engineering/file-structure.md](engineering/file-structure.md) |
| Engineer — code patterns | [engineering/conventions.md](engineering/conventions.md) |
| Engineer — adding features | [engineering/extending.md](engineering/extending.md) |

## Quick facts

- **Platform**: iOS only (SwiftUI, iOS 17+)
- **UI language**: Indonesian
- **Bible translation**: TB — Terjemahan Baru (© Lembaga Alkitab Indonesia, 1974)
- **Lectionary**: Roman Rite, daily Mass readings
- **Offline-first**: Bundled Bible seed + 5-year lectionary (no account, no ads)
- **External dependencies**: None (no CocoaPods, no SPM packages)
- **Lectionary regions**: Indonesia (KWI), United States (USCCB), Philippines (CBCP)

## Repository layout

```
BibleApp-Claude/       ← this repo (scripts, tools, docs)
BibleApp/              ← Xcode project
  BibleApp/            ← Swift source files (25 files)
  BibleApp.xcodeproj/
docs/                  ← this documentation folder
  product/
  engineering/
```
