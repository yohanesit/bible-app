# User Flows

This document walks through every major user journey in Lectio, step by step. Use it for design reviews, QA planning, and onboarding.

---

## 1. First launch

What happens the very first time a user opens the app.

```
App opens
  └─ Background: prefetch lectionary for current + next year (silent)
  └─ Foreground: ContentView renders
       └─ DailyMassView shows today's celebration name + readings
            ├─ Bible text is already seeded → readings display fully ✓
            └─ If a passage is outside the seed → "Sync needed" banner appears
                  └─ User taps gear icon in sidebar → Settings sheet opens
                        └─ (See flow 6: Admin sync)
```

**Key detail**: The Bible seed (`bible_seed.json`) is bundled in the app, so on a typical first launch all reading text displays immediately. The sync banner only appears if a specific passage is absent from the seed (rare edge case).

---

## 2. Reading today's Mass (primary flow)

The most common daily use of the app.

1. Open the app. The center view shows today's date and celebration name (e.g., "Senin, Masa Paskah") centered at the top.
2. Below the title: an accent divider line, then readings listed in liturgical order.
3. Each reading block shows:
   - **Type label** in small caps (e.g., BACAAN 1, MAZMUR TANGGAPAN, BACAAN INJIL)
   - **Scripture reference** in italics (e.g., Kis 2:14, 22-33)
   - **Intro rubric** (e.g., "Bacaan dari Kisah Para Rasul.")
   - **Body text** in the selected font and size
   - **Response rubric + congregation response** at the end of each reading
4. For the responsorial psalm: the sung refrain (from Lagumisa) appears above the body as "Ulangan: [refrain text]", and the refrain line "R. [refrain]" is inserted between each strophe group.
5. Scroll down to read through all readings.
6. Tap anywhere in the reading area to enter **immersive reading mode** — the bottom bar and status bar fade out.
7. Scroll back to the top (or tap again) to exit immersive reading mode and see the navigation controls.

**Status states the user may encounter:**

| Banner | Meaning | Action |
|---|---|---|
| Spinner + "Memuat bacaan…" | Loading from network/disk | Wait |
| "Sinkronkan Alkitab untuk membaca teks lengkap" | Bible text missing for one or more passages | Open Settings → Admin → Sync |
| "Menampilkan bacaan tersimpan. Sambungkan internet untuk memperbarui." | Offline; showing cached or bundled data | No action needed for reading; connect internet to refresh |
| Red error banner | Network + cache + bundle all failed | Check internet; if recurring, report bug |

---

## 3. Navigate to a different date

1. Tap the **secondary title** (the date label) in the bottom bar — the left sidebar slides in.
2. In the sidebar, tap the **"Lectionary"** row to expand the date grid.
3. A 10-day calendar appears: 7 days in the past, today (highlighted), and 2 days ahead.
4. Tap any date — the sidebar closes and the reading for that date loads.

```
Bottom bar (date tap)
  └─ Left pane slides in
       └─ Tap "Lectionary" row → date grid expands inline
            └─ Tap a date
                 └─ Pane closes → DailyReadingProvider.loadDay(selectedDate) →
                      reading for that date appears in center view
```

**Note**: The date window (7 past, today, 2 ahead) is computed by `DailyPaneCalendar`. Dates outside this window are not selectable from the UI.

---

## 4. Read a Bible chapter

1. Tap the **primary title** (book name, or "Hari Ini" on the daily view) in the bottom bar — the left sidebar slides in. Alternatively, swipe right from the left edge.
2. Scroll through the 73 books, organized by section: Perjanjian Lama → Deuterokanonika → Perjanjian Baru.
3. Tap a book row (e.g., "Matius — 28 Pasal") to expand an inline chapter grid.
4. Tap a chapter number — the sidebar closes and that chapter renders in the center view.
5. The chapter header shows the book name and chapter number. Verses flow continuously:
   - **Verse numbers**: small superscript in the accent color, inline with the text
   - **Section headings**: full-width heading above the relevant verse group
   - **Paragraph breaks**: visual spacing between paragraph groups
6. Tap anywhere to enter immersive reading mode (same as daily view).

---

## 5. Change appearance (theme, font, spacing)

1. Tap the **palette icon** in the bottom bar — the Preferences sheet slides up from the bottom.
2. **Theme**: Three cards — Purba (Classic), Abadi (Roman), Kini (Modern). Tap a card to switch. A filled 2px border shows the active theme.
3. **Day/Night/System**: One button that cycles through three modes (Light → Dark → System → Light…). The icon updates to sun / moon / half-circle.
4. **Font size**: Tap the **−A** or **+A** buttons to step through 8 sizes (12 pt → 14 → 16 → 18 → 20 → 21 → 22 → 24 pt). Dot indicators appear briefly below the buttons and fade after ~1 second.
5. **Line spacing**: Tap the spacing **−** or **+** buttons to step through 9 levels (Rapat → Normal → Lapang, etc.). Same dot indicator behavior.
6. All changes apply live as the sheet is open — the reading behind it updates in real time.
7. Swipe down (drag > 60 pt) or tap outside to dismiss.

---

## 6. Admin: download the full Bible text

Needed only once (or after a major update). Requires a free API key from bible-api.alkitab.or.id.

1. Tap the **gear icon** at the bottom of the sidebar → Settings sheet opens.
2. In Settings, the top section shows the current lectionary region and Bible version (TB).
3. Scroll to "Data & Sinkronisasi" and tap to open the Admin sheet.
4. In Admin:
   - **Books stored**: shows how many books are on-device (73 if fully synced, partial otherwise)
   - **Last sync**: date of last successful sync, or "Belum pernah" (Never)
   - **API Key field**: tap, paste your alkitab.or.id API key, tap "Simpan"
5. Tap **"Unduh Alkitab"** (first sync) or **"Perbarui Alkitab"** (re-sync). A confirmation dialog appears.
6. Confirm → a progress bar appears showing: current book name + percentage complete.
7. Sync downloads 66 books (OT + NT) chapter-by-chapter. The 7 Deuterocanonical books come from the bundled seed and are not re-downloaded.
8. On completion, progress disappears and "Last sync" updates to today's date. Bible text is now fully available for all readings.

**If sync fails:** A red error message appears below the progress bar. The sync can be retried by tapping Sync again. Partial data from a cancelled or failed sync is preserved — the next sync picks up where it left off (books already stored remain intact).

---

## 7. Change lectionary region

1. Tap the **gear icon** in the sidebar footer → Settings sheet.
2. Tap the **Lectionary Region** dropdown (shows current region with flag: e.g., "🇮🇩 Indonesia").
3. Select a region from the menu:
   - 🇮🇩 Indonesia (KWI)
   - 🇺🇸 United States (USCCB)
   - 🇵🇭 Philippines (CBCP)
4. The sheet closes. Today's reading reloads with the selected region's feast day overrides applied.

**Effect**: Regional overrides replace the entire day's readings and celebration name on feast days specific to that region (e.g., a local patron saint's day). On days with no regional override, all regions show identical readings.

---

## 8. Offline use scenarios

Lectio is designed to work without internet in all normal reading scenarios.

| Scenario | What the user sees |
|---|---|
| Bundled data covers the date (typical) | Reading appears instantly, no banner |
| Bundled data unavailable; disk cache exists | Reading appears; faint "Menampilkan bacaan tersimpan" banner |
| No bundle, no cache, no network | Error banner; app prompts to connect internet |
| Bible text missing for a passage | Individual reading shows "Teks belum tersedia. Sinkronkan Alkitab melalui Pengaturan › Admin." |
| Bible text present but app just launched | Text appears within < 100ms (local file read) |

The lectionary bundles cover 2026–2030. After 2030, the app will fall back to the network cache and then the live cpbjr API.
