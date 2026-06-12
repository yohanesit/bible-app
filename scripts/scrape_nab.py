#!/usr/bin/env python3
"""
scrape_nab.py — Scrape the NABRE from the USCCB website.

Source:  https://bible.usccb.org/bible/{book}/{chapter}
Output:  generated/bible_seed_nab.json

Usage:
    pip3 install requests beautifulsoup4
    python3 scripts/scrape_nab.py

The output matches the existing bible_seed.json schema so BibleDatabase
can expand it into the NAB source tree on first launch.

Copyright note: NABRE © Confraternity of Christian Doctrine. Personal use only.
For App Store distribution contact USCCB permissions: 202-541-3098.
"""

import json
import re
import time
import sys
from pathlib import Path

import requests
from bs4 import BeautifulSoup, NavigableString, Tag

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BASE_URL = "https://bible.usccb.org/bible"
OUT_FILE = Path(__file__).parent.parent / "generated" / "bible_seed_nab.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9",
}

DELAY_CHAPTER = 0.5   # seconds between chapter fetches
DELAY_BOOK    = 1.5   # seconds between books

# ---------------------------------------------------------------------------
# Book table: (USCCB URL slug, app slug, chapter count)
# ---------------------------------------------------------------------------

BOOKS = [
    # Old Testament
    ("genesis",        "kej",  50),
    ("exodus",         "kel",  40),
    ("leviticus",      "ima",  27),
    ("numbers",        "bil",  36),
    ("deuteronomy",    "ul",   34),
    ("joshua",         "yos",  24),
    ("judges",         "hak",  21),
    ("ruth",           "rut",   4),
    ("1samuel",        "1sam", 31),
    ("2samuel",        "2sam", 24),
    ("1kings",         "1raj", 22),
    ("2kings",         "2raj", 25),
    ("1chronicles",    "1taw", 29),
    ("2chronicles",    "2taw", 36),
    ("ezra",           "ezr",  10),
    ("nehemiah",       "neh",  13),
    # Deuterocanonical
    ("tobit",          "tob",  14),
    ("judith",         "ydt",  16),
    ("esther",         "est",  10),
    ("1maccabees",     "1mak", 16),
    ("2maccabees",     "2mak", 15),
    # Wisdom books
    ("job",            "ayb",  42),
    ("psalms",         "mzm", 150),
    ("proverbs",       "ams",  31),
    ("ecclesiastes",   "pkh",  12),
    ("songofsongs",    "kid",   8),
    ("wisdom",         "keb",  19),
    ("sirach",         "sir",  51),
    # Prophets
    ("isaiah",         "yes",  66),
    ("jeremiah",       "yer",  52),
    ("lamentations",   "rat",   5),
    ("baruch",         "bar",   6),
    ("ezekiel",        "yeh",  48),
    ("daniel",         "dan",  14),  # 14 in NABRE (incl. deuterocanonical additions)
    ("hosea",          "hos",  14),
    ("joel",           "yol",   4),  # 4 in NABRE
    ("amos",           "amo",   9),
    ("obadiah",        "oba",   1),
    ("jonah",          "yun",   4),
    ("micah",          "mik",   7),
    ("nahum",          "nah",   3),
    ("habakkuk",       "hab",   3),
    ("zephaniah",      "zef",   3),
    ("haggai",         "hag",   2),
    ("zechariah",      "zak",  14),
    ("malachi",        "mal",   3),
    # New Testament
    ("matthew",        "mat",  28),
    ("mark",           "mrk",  16),
    ("luke",           "luk",  24),
    ("john",           "yoh",  21),
    ("acts",           "kis",  28),
    ("romans",         "rom",  16),
    ("1corinthians",   "1kor", 16),
    ("2corinthians",   "2kor", 13),
    ("galatians",      "gal",   6),
    ("ephesians",      "ef",    6),
    ("philippians",    "flp",   4),
    ("colossians",     "kol",   4),
    ("1thessalonians", "1tes",  5),
    ("2thessalonians", "2tes",  3),
    ("1timothy",       "1tim",  6),
    ("2timothy",       "2tim",  4),
    ("titus",          "tit",   3),
    ("philemon",       "flm",   1),
    ("hebrews",        "ibr",  13),
    ("james",          "yak",   5),
    ("1peter",         "1ptr",  5),
    ("2peter",         "2ptr",  3),
    ("1john",          "1yoh",  5),
    ("2john",          "2yoh",  1),
    ("3john",          "3yoh",  1),
    ("jude",           "yud",   1),
    ("revelation",     "why",  22),
]

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

SESSION = requests.Session()
SESSION.headers.update(HEADERS)


def fetch(url: str, retries: int = 3) -> str:
    for attempt in range(retries):
        try:
            r = SESSION.get(url, timeout=30)
            r.raise_for_status()
            return r.text
        except Exception as exc:
            wait = 2 ** attempt
            print(f"  ⚠ fetch error ({exc}), retrying in {wait}s…", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"Failed to fetch {url} after {retries} attempts")


# ---------------------------------------------------------------------------
# Parsing
#
# Actual USCCB HTML structure (confirmed by page inspection):
#
#   <div id="scribeI" class="contentarea">
#     <h3 class="ch">CHAPTER 1</h3>          ← skip (chapter number label)
#     <h3 class="cs">The Story of Creation.</h3>  ← section heading
#     <h4 class="chsect">The Beatitudes</h4>     ← subsection heading
#     <p class="pf">
#       <b>Inline heading.</b>                ← also a section heading; remove before walking
#       <a name="..."><span class="bcv">1</span>verse text...</a>
#     </p>
#     <p class="po" id="..."><span class="bcv">2</span>verse text</p>
#     <p class="poi">poetry continuation line</p>  ← no bcv → append to last verse
#     <p class="pof">poetry continuation line</p>  ← no bcv → append to last verse
#   </div>
#
# Poetry continuation classes (no bcv span = continuation of previous verse):
#   pof, poi, poi2, poil, po, po2  — but only when they have NO bcv span.
# ---------------------------------------------------------------------------

_ROMAN_RE   = re.compile(r"^[IVXivx]+$")   # Roman numerals used as subsection dividers
_POETRY_CLS = {"pof", "poi", "poi2", "poil", "po", "po2"}


def _strip_footnotes(elem: Tag) -> None:
    """Remove footnote/cross-ref links and superscripts from an element in-place."""
    for a in elem.find_all("a", class_=["fnref", "enref"]):
        a.decompose()
    for sup in elem.find_all("sup"):
        sup.decompose()


def _clean(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _extract_verses_from_p(p: Tag) -> list[tuple[int, str]]:
    """
    Walk a <p> element and return (verse_num, text) pairs, splitting at each
    <span class="bcv">. Footnote links and <sup> markers are silently dropped.
    """
    results: list[tuple[int, str]] = []
    current_num: list[int | None] = [None]   # use list for mutability in nested fn
    current_parts: list[str]      = []

    def flush() -> None:
        if current_num[0] is None:
            return
        t = _clean(" ".join(current_parts))
        if t:
            results.append((current_num[0], t))
        current_num[0] = None
        current_parts.clear()

    def walk(node: Tag) -> None:
        for child in node.children:
            if isinstance(child, NavigableString):
                current_parts.append(str(child))
            elif isinstance(child, Tag):
                if child.name == "span" and "bcv" in child.get("class", []):
                    flush()
                    try:
                        current_num[0] = int(child.get_text(strip=True))
                    except ValueError:
                        pass
                elif child.name == "br":
                    current_parts.append(" ")
                elif child.name == "a" and any(
                    c in child.get("class", []) for c in ("fnref", "enref")
                ):
                    pass   # drop footnote link
                elif child.name == "sup":
                    pass   # drop superscript marker
                else:
                    walk(child)

    walk(p)
    flush()
    return results


def parse_chapter(html: str) -> list[dict]:
    """
    Parse one USCCB chapter page into a list of verse dicts:
      {"v": int, "t": str}  or  {"v": int, "t": str, "h": str}
    """
    soup = BeautifulSoup(html, "html.parser")

    content = soup.find("div", id="scribeI") or soup.find("div", class_="contentarea")
    if not content:
        return []

    verses:          list[dict]   = []
    pending_heading: str | None   = None

    for elem in content.find_all(["h3", "h4", "p"]):
        if not isinstance(elem, Tag):
            continue

        tag     = elem.name
        classes = set(elem.get("class", []))

        # ── Chapter label (CHAPTER N / PSALM N) ── skip ──────────────────
        if tag == "h3" and "ch" in classes:
            continue

        # ── Section heading <h3 class="cs"> ──────────────────────────────
        if tag == "h3" and "cs" in classes:
            _strip_footnotes(elem)
            text = _clean(elem.get_text())
            if text:
                pending_heading = text
            continue

        # ── Subsection heading <h4 class="chsect"> ───────────────────────
        if tag == "h4" and "chsect" in classes:
            _strip_footnotes(elem)
            text = _clean(elem.get_text())
            # Skip Roman numeral dividers (I, II, III…) — decorative only
            if text and not _ROMAN_RE.match(text) and not text.isdigit():
                pending_heading = text
            continue

        # ── Paragraph ─────────────────────────────────────────────────────
        if tag != "p":
            continue

        # Check for inline heading (<b> or <strong> before first bcv span)
        if "pf" in classes:
            for htag in elem.find_all(["b", "strong"]):
                htext = _clean(htag.get_text())
                if htext and not htext.isdigit():
                    pending_heading = htext
                    htag.decompose()  # remove so it won't leak into verse text
                    break

        # Find verse-number spans
        bcv_spans = elem.find_all("span", class_="bcv")

        if not bcv_spans:
            # Poetry / prose continuation — append to the last verse
            if classes & _POETRY_CLS and verses:
                _strip_footnotes(elem)
                continuation = _clean(elem.get_text())
                if continuation:
                    verses[-1]["t"] += " " + continuation
            continue

        # Extract verse(s) from this paragraph
        for verse_num, verse_text in _extract_verses_from_p(elem):
            entry: dict = {"v": verse_num, "t": verse_text}
            if pending_heading:
                entry["h"] = pending_heading
                pending_heading = None
            verses.append(entry)

    verses.sort(key=lambda x: x["v"])
    return verses


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    output_books: dict[str, dict] = {}
    total = len(BOOKS)

    for idx, (url_slug, app_slug, chapter_count) in enumerate(BOOKS, 1):
        print(f"[{idx:2d}/{total}] {url_slug} ({app_slug}) — {chapter_count} chapters")
        book_data: dict[str, list] = {}

        for ch in range(1, chapter_count + 1):
            url = f"{BASE_URL}/{url_slug}/{ch}"
            try:
                html   = fetch(url)
                verses = parse_chapter(html)
                if verses:
                    book_data[str(ch)] = verses
                    headings = sum(1 for v in verses if v.get("h"))
                    print(f"    ch {ch:3d}: {len(verses):3d} verses, {headings} headings")
                else:
                    print(f"    ch {ch:3d}: ⚠ no verses parsed — {url}", file=sys.stderr)
            except Exception as exc:
                print(f"    ch {ch:3d}: ERROR — {exc}", file=sys.stderr)

            if ch < chapter_count:
                time.sleep(DELAY_CHAPTER)

        output_books[app_slug] = book_data
        if idx < total:
            time.sleep(DELAY_BOOK)

    seed = {
        "version":     "nab",
        "seedVersion": 1,
        "note":        "NABRE — scraped from bible.usccb.org for personal use",
        "books":       output_books,
    }

    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(seed, f, ensure_ascii=False, separators=(",", ":"))

    total_verses   = sum(len(vl) for bd in output_books.values() for vl in bd.values())
    total_headings = sum(
        1 for bd in output_books.values()
        for vl in bd.values()
        for v in vl if v.get("h")
    )
    print(f"\nDone.")
    print(f"  {len(output_books)} books, {total_verses:,} verses, {total_headings:,} headings")
    print(f"  Output: {OUT_FILE}")
    print()
    print("Next steps:")
    print("  1. Copy generated/bible_seed_nab.json → BibleApp/BibleApp/bible_seed_nab.json")
    print("  2. In Xcode: add file to BibleApp target")


if __name__ == "__main__":
    main()
