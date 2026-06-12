# External API Reference

Lectio uses two external HTTP APIs. Neither is required for basic reading (both have bundled/cached fallbacks), but both are required for content updates.

---

## 1. cpbjr Catholic Readings API (lectionary citations)

### Purpose
Provides lightweight scripture citations for each day's Mass readings. Does **not** return Bible verse text — only references like "Acts 4:13-21".

### Endpoint

```
GET https://cpbjr.github.io/catholic-readings-api/readings/{YEAR}/{MM-DD}.json
```

- `{YEAR}` — 4-digit year, e.g. `2026`
- `{MM-DD}` — zero-padded month and day, e.g. `04-26`

### Request
No authentication required. No custom headers needed.

### Example request
```
GET https://cpbjr.github.io/catholic-readings-api/readings/2026/04-26.json
```

### Example response
```json
{
  "date": "2026-04-26",
  "season": "Eastertide",
  "celebration": "Third Sunday of Easter",
  "readings": {
    "firstReading": "Acts 5:27-32, 40-41",
    "psalm": "Psalm 30:2 and 4, 5-6, 11-12a and 13b",
    "secondReading": "Revelation 5:11-14",
    "gospel": "John 21:1-19"
  }
}
```

Fields:
| Field | Type | Notes |
|---|---|---|
| `date` | string | ISO 8601 date |
| `season` | string | English season name (e.g. "Eastertide", "Advent", "Lent", "Ordinary Time") |
| `celebration` | string | Optional; English celebration name for feasts/solemnities |
| `readings.firstReading` | string | Citation, always present |
| `readings.psalm` | string | Responsorial psalm citation, always present |
| `readings.secondReading` | string or null | null on ferias and some memorials |
| `readings.gospel` | string | Citation, always present |

### Timeouts
- Request timeout: 10 seconds
- Resource timeout: 20 seconds

### Disk cache
All responses are cached to disk at:
```
Library/Caches/lectionary/{YEAR}/{MM-DD}.json
```
The cache is permanent (no TTL). It is read as a fallback when the network is unavailable.

### Prefetch
On every app launch, `LectionaryService.prefetchYearIfNeeded()` runs in a background `Task`. It iterates all days of the current year and the next year and fetches any that are not yet in the disk cache. This runs silently and does not block the UI.

### Error handling
| Condition | Behavior |
|---|---|
| 200 OK | Decode and return `LectionaryDay` |
| 404 Not Found | Treated as "date not covered"; fall back to disk cache |
| Network unavailable | Skip network; fall back to disk cache |
| Disk cache also absent | `LectionaryService` throws `LectionaryServiceError.notFound` |
| Decode error | Throws `LectionaryServiceError.decodingError` |

The caller (`DailyReadingProvider`) catches these errors and sets `DayLoadState.error(message)` or `DayLoadState.offline(massDay)` as appropriate.

### Implementation location
`BibleApp/BibleApp/LectionaryService.swift`

---

## 2. alkitab.or.id Bible API (full text sync)

### Purpose
Provides the full verse-by-verse text of the TB (Terjemahan Baru) Bible. Used only by the admin sync panel to populate the local `BibleDatabase`. **Not called during normal reading.**

### Endpoint

```
GET https://bible-api.alkitab.or.id/bible/tb/{book_slug}/{chapter}
```

- `{book_slug}` — lowercase book abbreviation matching alkitab.or.id conventions (e.g. `kej`, `mat`, `why`, `1kor`)
- `{chapter}` — integer chapter number (e.g. `1`, `28`)

### Authentication
```
Authorization: Bearer {API_KEY}
```
The API key is stored in `UserDefaults("alkitabApiKey")`. Obtain a free key by registering at `bible-api.alkitab.or.id`.

### Example request
```
GET https://bible-api.alkitab.or.id/bible/tb/mat/5
Authorization: Bearer your-api-key-here
```

### Response — format A (most common)
```json
{
  "book": "mat",
  "chapter": 5,
  "verses": [
    { "verse": 1, "text": "Ketika Yesus melihat orang banyak itu...", "heading": "Ucapan Bahagia" },
    { "verse": 2, "text": "lalu Ia pun mulai berbicara..." },
    ...
  ]
}
```

### Response — format B (some endpoints)
```json
{
  "data": [
    { "v": 1, "t": "Ketika Yesus melihat..." },
    { "v": 2, "t": "lalu Ia pun..." }
  ]
}
```

`BibleSyncService` handles both formats via flexible `Codable` models that try multiple field names (`verse`/`v`/`number` for the verse number, `text`/`t`/`content` for the text, `heading`/`h`/`title` for headings).

### Verse object fields
| Field | Alternatives | Type | Notes |
|---|---|---|---|
| `verse` | `v`, `number` | Int | Verse number |
| `text` | `t`, `content` | String | Verse text |
| `heading` | `h`, `title` | String? | Section heading before this verse |

### Timeouts
- Request timeout: 15 seconds
- Resource timeout: 30 seconds (longer because some books are large)

### Coverage
- **66 books**: 39 Old Testament + 27 New Testament
- **Not covered**: 7 Deuterocanonical books (Tobit, Judith, 1 & 2 Maccabees, Wisdom, Sirach, Baruch) — these come from the bundled seed only

### Sync flow
`BibleSyncService.runSync()` iterates over a hard-coded manifest of 66 books with their chapter counts (`tbChapterCounts`). For each book, it:
1. Fetches every chapter sequentially
2. Accumulates `BibleVerse` arrays into `BibleBookData`
3. After all chapters for a book: calls `BibleDatabase.shared.writeBook(data, slug:, toSource:)`
4. Updates `progress` and `currentBook` on `@MainActor` for UI

### Error handling
| Condition | Behavior |
|---|---|
| 401 Unauthorized | Sets `error` on `BibleSyncService`; sync stops |
| Network timeout | Sets `error`; sync stops at current book |
| Decode error for a chapter | Logs error; continues to next chapter (partial book written) |
| Task cancelled | Stops at current book; all fully-written books preserved |
| No API key | Sync button is disabled; sync cannot start |

### Implementation location
`BibleApp/BibleApp/BibleSyncService.swift`

---

## Error handling summary

| Error | LectionaryService | BibleSyncService |
|---|---|---|
| No network | Fall back to disk cache; if absent → throw `notFound` | Set `error` string; stop sync |
| 404 / not found | Fall back to disk cache | N/A (full manifest used) |
| Decode error | Throw `decodingError` | Log and skip chapter; continue |
| Auth failure | N/A (no auth) | Set `error` string; stop sync |
| No API key | N/A | Sync button disabled; cannot start |
| Task cancelled | N/A | Stop; partial data preserved |
