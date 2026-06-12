# Feature Reference

Detailed behavior documentation for each feature, including edge cases and state models. Use this for QA test planning and product spec reviews.

---

## Daily Mass Lectionary

### What it is
Shows the complete Catholic Mass readings for a selected date: up to four readings in liturgical order, including their type labels, scripture references, intro rubrics, body text, and congregational responses.

### Date window
The selectable date range is **7 days in the past + today + 2 days ahead** (10 days total). This is computed by `DailyPaneCalendar` and displayed as a horizontal grid in the sidebar's Lectionary accordion.

### Reading types (in order)
| Label | Indonesian | Condition |
|---|---|---|
| BACAAN 1 | First Reading | Every day |
| MAZMUR TANGGAPAN | Responsorial Psalm | Every day |
| BACAAN 2 | Second Reading | Sundays and solemnities only |
| BAIT PENGANTAR INJIL | Gospel Acclamation (Alleluia) | Present in data but not always rendered |
| BACAAN INJIL | Gospel | Every day |

### Responsorial psalm structure
The psalm is not displayed as a continuous block. It is split into a refrain and strophe groups:
1. The **Lagumisa sung refrain** (if available for this date) appears above the body as "Ulangan: [text]"
2. The **congregation refrain** is inserted between each strophe group as "R. [text]"
3. Strophe groups are separated by this refrain line, mirroring the call-and-response structure of sung Mass

### State model
`DayLoadState` drives the entire view. States:

| State | UI shown |
|---|---|
| `idle` | Nothing (brief; transitions to `loading` immediately) |
| `loading` | Spinner + "Memuat bacaan…" text |
| `loaded(MassDay)` | Full reading content |
| `needsSync(MassDay)` | Full content + amber banner: "Sinkronkan Alkitab untuk membaca teks lengkap" |
| `offline(MassDay)` | Full content + muted banner: "Menampilkan bacaan tersimpan. Sambungkan internet untuk memperbarui." |
| `error(String)` | Red error banner with the error message string |

In `needsSync`, the reading is displayed but one or more verse texts are absent or truncated because the relevant book has not been synced from the API. The user can still see the reference and rubrics.

### Celebration name and season
The celebration name (e.g., "Senin Dalam Oktaf Paskah") comes from the lectionary data. The liturgical season is used for semantic color selection in the theme system — though currently all seasons share the same palette, the infrastructure is in place for season-aware theming.

---

## Bible Reader

### What it is
Displays any chapter of any of the 73 Catholic Bible books, formatted with inline verse numbers, section headings, and paragraph breaks.

### Book navigation
All 73 books are listed in the sidebar in canonical order:
- Perjanjian Lama (Old Testament): 39 books
- Deuterokanonika (Deuterocanonical): 7 books
- Perjanjian Baru (New Testament): 27 books

Each book row shows the Indonesian book name and chapter count (e.g., "Matius — 28 Pasal"). Tapping a row expands an inline chapter grid. Chapters are displayed as a 7-column number grid; tapping a number loads that chapter.

### Verse rendering
Verses are displayed in a continuous text flow:
- **Verse numbers**: inline, smaller than body text (~58% of body size), colored in the accent color, positioned as superscript
- **Section headings**: appear before relevant verse groups as uppercase/small-caps headings; break the text flow visually
- **Paragraph breaks**: extra spacing is added between verse groups where `p: true` is set on the first verse of a new paragraph

### State model
`ChapterLoadState` drives the view:

| State | UI shown |
|---|---|
| `idle` | Nothing |
| `loaded(bookName, chapter, verses)` | Full chapter with header and verses |
| `empty(bookName, chapter)` | Header + message: "Teks belum tersedia. Sinkronkan Alkitab melalui Pengaturan › Admin." |

`empty` means the book exists in the catalog but its JSON file is not on disk — the book was not in the seed and has not been synced. The user needs to run the admin sync.

---

## Themes

### Overview
Four themes, each representing a typographic aesthetic:

| Theme | Name | Font family | Character |
|---|---|---|---|
| Purba | Klasik | Valkyrie B | Warm, traditional, serif |
| Abadi | Roman | Heliotrope 4 Tab | Neutral, classic, serif |
| Kini | Modern | IBM Plex Mono | Clean, minimal, monospace |
| System | Sistem | SF Pro Display | Follows iOS system font |

Regardless of theme, **all display titles** (celebration name, book name, chapter number) use **Valkyrie B Caps** — this gives the app a consistent typographic identity even when the body text changes.

### Color palettes
Each theme has two independent palettes: one for day mode, one for night mode. That gives 6 distinct palettes total (plus System, which delegates to iOS light/dark).

| Theme | Day background | Night background | Accent |
|---|---|---|---|
| Purba Day | Warm beige (#FAF9F6) | — | Warm gold |
| Purba Night | — | Dark brown | Muted gold |
| Abadi Day | Cool light gray (#F2F0EC) | — | Blue-gray |
| Abadi Night | — | Near black (#060606) | Muted blue |
| Kini Day | Near white (#FAFAF8) | — | Olive green |
| Kini Night | — | Dark green-tinted | Bright green |

### Semantic color roles
The theme system uses named roles, not raw hex values:

| Role | Purpose |
|---|---|
| `background` | Main page background |
| `surface` | Cards, sheets, overlays |
| `border` | Dividers, separators |
| `accent` | Verse numbers, selected items, decorative lines |
| `textPrimary` | Body reading text |
| `textSecondary` | Labels, captions, rubric text |
| `rubric` | Intro/response rubric text (liturgical red in some traditions) |
| `congregationResponse` | Congregation response lines |

---

## Typography controls

### Font size
8 discrete stops accessible via the − / + buttons in Preferences:

| Stop | Size | Default? |
|---|---|---|
| 1 | 12 pt | |
| 2 | 14 pt | |
| 3 | 16 pt | |
| 4 | 18 pt | |
| 5 | 20 pt | ✓ Default |
| 6 | 21 pt | |
| 7 | 22 pt | |
| 8 | 24 pt | |

The dot indicator below the buttons shows 8 dots; the active dot is filled. It auto-hides after ~1.1 seconds of inactivity.

### Line spacing
9 discrete stops:

| Stop | Label | Added space | Default? |
|---|---|---|---|
| 1 | Rapat (Tight) | ~0 pt | |
| 2 | Sempit (Snug) | ~2 pt | |
| 3 | Kompak (Compact) | ~4 pt | |
| 4 | Nyaman (Cozy) | ~6 pt | |
| 5 | Seimbang (Balanced) | ~8 pt | |
| 6 | Normal | ~10 pt | ✓ Default |
| 7 | Santai (Relaxed) | ~12 pt | |
| 8 | Longgar (Loose) | ~14 pt | |
| 9 | Lapang (Airy) | ~16 pt | |

Line spacing applies to body text only (readings and Bible verses). It does not affect UI labels.

---

## Offline and first-run setup

### Bible seed expansion
On first launch (and on any launch where the bundled seed version is newer than what is already on disk), `BibleDatabase.expandSeedIfNeeded()` runs:
1. Reads `bible_seed.json` from the app bundle
2. Checks the `seedVersion` integer inside the bundle against `UserDefaults("bibleSeedBundleRevision")`
3. If bundle version is higher: writes each book's JSON to `Documents/bible/tb/{slug}.json`
4. Updates `UserDefaults("bibleSeedBundleRevision")` to the new version
5. Writes a `.seeded` sentinel file in the `tb/` directory

This process is synchronous and happens before the first view render. After it completes, all seeded books are available for reading.

### Bundled lectionary coverage
Five year-files are bundled: `lectionary_2026.json` through `lectionary_2030.json`. Each file covers all 365–366 days of that liturgical year. `BundledLectionaryStore` loads these files lazily (on first access for that year) and caches them in memory.

After 2030, the app uses the network lectionary API with disk caching. There is no user-facing warning when bundled coverage expires — the transition is seamless as long as network is available.

### Background prefetch
On every app launch, `LectionaryService.prefetchYearIfNeeded()` runs in a background `Task`. It fetches all un-cached days for the current year and the next year from the cpbjr API and saves them to `Library/Caches/lectionary/`. This means cached network data is always ready for offline use before the user needs it.

---

## Regional lectionary overrides

### How it works
`lectionary_overrides.json` is bundled in the app. Its structure:
```
{
  "regions": {
    "ID": { "name": "Indonesia (KWI)", "flag": "🇮🇩" },
    "US": { "name": "United States (USCCB)", "flag": "🇺🇸" },
    "PH": { "name": "Philippines (CBCP)", "flag": "🇵🇭" }
  },
  "overrides": {
    "ID": {
      "2026": {
        "08-17": { ... }   ← Independence Day saint override
      }
    }
  }
}
```

### Resolution priority
When looking up a date, `BundledLectionaryStore` resolves in this order:
1. `overrides[selectedRegion][year][MM-DD]` — region-specific override (highest priority)
2. `lectionary_YYYY.json[MM-DD]` — base year data
3. `nil` — falls back to network API

An override replaces the **entire day** — all readings and the celebration name are taken from the override entry. There is no partial override.

### Displayed regions
The Settings region picker reads `availableRegions` from `BundledLectionaryStore`, which returns all keys from the `"regions"` object in the overrides file. Adding a new region requires only updating the JSON bundle — no Swift code changes.

---

## Admin panel

### Access
Gear icon in the sidebar footer → Settings sheet → "Data & Sinkronisasi" section.

### What it shows
- **Books stored**: count of book JSON files currently on-device for the active source
- **Last sync**: date of last completed sync, or "Belum pernah" (Never)
- **API Key input**: `SecureField`; shows "Simpan" button when the value differs from what is stored

### Sync behavior
- The sync button is disabled if no API key has been saved
- Before sync starts, a confirmation dialog appears: "Akan mengunduh teks TB dari alkitab.or.id secara lokal."
- During sync: progress bar (0–100%), current book name, and a Cancel button are shown
- If cancelled: sync stops at the current book; all fully-written books are preserved; partially written book data is discarded
- On completion: `lastBibleSync` UserDefaults key is updated; progress UI disappears
- On error: a red message appears below the progress bar; sync stops

### What is and is not synced
- **Synced**: 66 books (39 OT + 27 NT) via alkitab.or.id API
- **Not synced**: 7 Deuterocanonical books — these come from the bundled seed only. alkitab.or.id does not publish them.
- **API key storage**: stored in `UserDefaults("alkitabApiKey")`, not the iOS Keychain. This is an accepted tradeoff for a developer-facing admin panel. See [decisions.md](decisions.md#api-key-storage) if this needs to change.
