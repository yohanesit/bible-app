# Product Overview

## Mission

Lectio exists to give Indonesian Catholics a beautifully typeset, always-offline-capable companion for the daily Mass and personal Bible reading. No accounts, no ads, no friction — open the app and the reading for today is already there.

## Target user

Indonesian-speaking Catholics who attend Mass regularly. The app is used before Mass to prepare, during Mass as a reference, and at home for personal reading. Users are comfortable with Indonesian; they do not need to be technically savvy. The app assumes no prior knowledge of the TB translation or lectionary structure — but it serves both beginners and daily practitioners equally.

## Core value propositions

- **Always works offline.** All lectionary data is bundled for five years (2026–2030) and Bible text is seeded on first launch. A network connection is never required for reading.
- **Typographically serious.** Three distinct font pairings (Valkyrie B, Heliotrope 4 Tab, IBM Plex Mono) with eight font sizes and nine line-spacing levels. Reading feels like a book, not a web page.
- **Liturgically accurate.** KWI-specific regional feast day overrides, correct responsorial psalm refrain structure (refrain inserted between strophes), and sung psalm refrains from Lagumisa.

---

## Feature inventory

| Feature | Status | Notes |
|---|---|---|
| Daily Mass Lectionary | Live | Shows readings for any date ±7 days |
| Bible Reader — 73 books | Live | All OT, Deuterocanonical, and NT books |
| Theme: Purba (Classic) | Live | Valkyrie B serif, warm palette |
| Theme: Abadi (Roman) | Live | Heliotrope 4 Tab serif, neutral palette |
| Theme: Kini (Modern) | Live | IBM Plex Mono, minimal palette |
| Theme: System | Live | SF Pro, follows iOS appearance |
| Font size control | Live | 8 stops: 12 pt – 24 pt |
| Line spacing control | Live | 9 stops: 100% – 180% |
| Day / Night mode | Live | Light, dark, or follow system |
| Regional Lectionary overrides | Live | Indonesia (KWI), US (USCCB), Philippines (CBCP) |
| Sung psalm refrain (Lagumisa) | Live | Bundled; shown above responsorial psalm |
| Admin sync panel | Live | Downloads full Bible text via alkitab.or.id API |
| Offline seed data | Live | Full TB text bundled; expands on first launch |
| Immersive reading mode | Live | Tap to hide all chrome; auto-hides on scroll |
| Gesture navigation | Live | Horizontal swipe opens/closes sidebar |

---

## Supported content

### Bible canon
All 73 books of the Catholic canon:
- **Old Testament (Perjanjian Lama)**: 39 books
- **Deuterocanonical (Deuterokanonika)**: 7 books — Tobit, Judith, 1 & 2 Maccabees, Wisdom of Solomon, Sirach (Ecclesiasticus), Baruch
- **New Testament (Perjanjian Baru)**: 27 books

### Bible translation
**TB — Terjemahan Baru** (Indonesian: "New Translation")
- Published by Lembaga Alkitab Indonesia (LAI), 1974
- Standard Indonesian Catholic and Protestant Bible
- Copyright © LAI — used in Lectio for personal, non-commercial reading

### Lectionary
- **Source**: cpbjr/catholic-readings-api (static JSON on GitHub Pages)
- **Bundled years**: 2026 – 2030 (five files, ~44 KB each)
- **Network fallback**: fetches dynamically when bundled year is not available
- **Regional overrides**: Indonesia KWI, United States USCCB, Philippines CBCP

### Bible text source (admin sync)
- **API**: bible-api.alkitab.or.id (alkitab.or.id project)
- **Coverage**: 66 books (OT + NT). The 7 Deuterocanonical books come from the bundled seed only (alkitab.or.id does not publish them).
- **Requires**: A free API key registered at bible-api.alkitab.or.id

---

## Platform and distribution

- **Platform**: iOS only (iPhone and iPad)
- **Minimum deployment**: iOS 17 (requires `@Observable` macro)
- **Distribution**: App Store
- **External frameworks**: None. No CocoaPods, no Swift Package Manager dependencies.
- **App size**: ~5–10 MB base (seed JSON + font files + bundled lectionary JSONs)

---

## Licensing and attribution

| Content | Source | License / Terms |
|---|---|---|
| TB Bible text | Lembaga Alkitab Indonesia (LAI) | © LAI 1974 — personal reading use |
| Daily lectionary citations | cpbjr/catholic-readings-api | Open; GitHub Pages static data |
| Imankatolik.or.id | Indonesian Catholic portal | Credited in Acknowledgements |
| Lagumisa sung refrains | lagumisa.web.id | Bundled via scraper; credited in Acknowledgements |
| Valkyrie B font | David Jonathan Ross | Licensed per font EULA |
| Heliotrope 4 Tab font | Klim Type Foundry | Licensed per font EULA |
| IBM Plex Mono | IBM / SIL OFL | Open Font License |
