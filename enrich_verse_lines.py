#!/usr/bin/env python3
"""
Fetches every chapter from the alkitab.or.id public HTML API and injects
within-verse poetry line structure into bible_seed.json.

API:  GET https://alkitab.or.id/api/bible/decrypt?edition=tb&kitab={name}&pasal={ch}
Auth: none
Returns: { "success": true, "html": "<html>…</html>" }

The HTML contains verse spans with optional verse_q1 / verse_q2 child divs
that represent the actual TB line breaks and indentation levels.  This script
extracts those into a "lines" field:

    { "v": 1, "t": "...", "q": 1,
      "lines": [{"t": "Berbahagialah orang",           "q": 1},
                {"t": "yang tidak berjalan …",          "q": 2},
                {"t": "yang tidak berdiri …",           "q": 1},
                {"t": "dan yang tidak duduk …",         "q": 2}] }

It also updates "q" on the verse from the first line's level, overriding
the coarser USFM-derived value written by enrich_paragraphs.py.

Usage:
    python3 enrich_verse_lines.py [--dry-run] [--book <slug>]

Options:
    --dry-run   Print proposed changes without writing anything
    --book      Only process a single book slug (e.g. mzm, yoh)
"""

from __future__ import annotations
import argparse
import json
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SEED_PATH = Path(__file__).parent / "BibleApp/BibleApp/bible_seed.json"
BASE_URL  = "https://alkitab.or.id/api/bible/decrypt"
DELAY     = 0.35   # seconds between requests — be polite

# ---------------------------------------------------------------------------
# Slug → kitab name (verified against the API)
# ---------------------------------------------------------------------------

SLUG_TO_KITAB: dict[str, str] = {
    "kej":  "kejadian",        "kel":  "keluaran",         "ima":  "imamat",
    "bil":  "bilangan",        "ul":   "ulangan",          "yos":  "yosua",
    "hak":  "hakim-hakim",     "rut":  "rut",              "1sam": "1-samuel",
    "2sam": "2-samuel",        "1raj": "1-raja-raja",      "2raj": "2-raja-raja",
    "1taw": "1-tawarikh",      "2taw": "2-tawarikh",       "ezr":  "ezra",
    "neh":  "nehemia",         "est":  "ester",            "ayb":  "ayub",
    "mzm":  "mazmur",          "ams":  "amsal",            "pkh":  "pengkhotbah",
    "kid":  "kidung-agung",    "yes":  "yesaya",           "yer":  "yeremia",
    "rat":  "ratapan",         "yeh":  "yehezkiel",        "dan":  "daniel",
    "hos":  "hosea",           "yol":  "yoel",             "amo":  "amos",
    "oba":  "obaja",           "yun":  "yunus",            "mik":  "mikha",
    "nah":  "nahum",           "hab":  "habakuk",          "zef":  "zefanya",
    "hag":  "hagai",           "zak":  "zakharia",         "mal":  "maleakhi",
    "mat":  "matius",          "mrk":  "markus",           "luk":  "lukas",
    "yoh":  "yohanes",         "kis":  "kisah-para-rasul", "rom":  "roma",
    "1kor": "1-korintus",      "2kor": "2-korintus",       "gal":  "galatia",
    "ef":   "efesus",          "flp":  "filipi",           "kol":  "kolose",
    "1tes": "1-tesalonika",    "2tes": "2-tesalonika",     "1tim": "1-timotius",
    "2tim": "2-timotius",      "tit":  "titus",            "flm":  "filemon",
    "ibr":  "ibrani",          "yak":  "yakobus",          "1ptr": "1-petrus",
    "2ptr": "2-petrus",        "1yoh": "1-yohanes",        "2yoh": "2-yohanes",
    "3yoh": "3-yohanes",       "yud":  "yudas",            "why":  "wahyu",
}

# Deuterocanonical books not in TB Protestant canon — skip
SKIP_SLUGS = {"tob", "ydt", "1mak", "2mak", "keb", "sir", "bar"}

# ---------------------------------------------------------------------------
# HTML parsing
# ---------------------------------------------------------------------------

# Matches the opening tag of a verse span and captures the idverse attribute.
# We split on this to get per-verse chunks rather than trying to match closing
# tags (tricky because <span class="versenumber"> nests inside the verse span).
_VERSE_OPEN_RE = re.compile(r'<span\s+class="verse"[^>]*idverse="([^"]+)"[^>]*>')
# Strips all HTML tags, collapses whitespace.
_TAG_RE = re.compile(r"<[^>]+>")

# Matches verse_q1 or verse_q2 div content.
_Q_DIV_RE = re.compile(
    r'<div\s+class="verse_(q[12])"[^>]*>(.*?)</div>',
    re.DOTALL,
)

def _clean(text: str) -> str:
    """Strip HTML tags and normalise whitespace."""
    text = _TAG_RE.sub("", text)
    return " ".join(text.split())


def _q_level(class_name: str) -> int:
    return 2 if class_name == "q2" else 1


def _strip_boilerplate(html: str) -> str:
    """Remove footer, header, and other non-verse content before parsing."""
    html = re.sub(r'<footer\b[^>]*>.*?</footer>', '', html, flags=re.DOTALL)
    html = re.sub(r'<header\b[^>]*>.*?</header>', '', html, flags=re.DOTALL)
    return html


def extract_verse_chunks(html: str) -> list[tuple[str, str]]:
    """
    Split the chapter HTML into (idverse, chunk) pairs where each chunk is
    the HTML content between one verse opening tag and the next.
    This avoids the nested-span issue with regex-based closing-tag matching.
    """
    parts = _VERSE_OPEN_RE.split(html)
    # parts[0]     = HTML before the first verse span
    # parts[1]     = idverse of verse 1
    # parts[2]     = HTML content of verse 1 (up to the next open tag)
    # parts[3]     = idverse of verse 2  … etc.
    chunks = []
    for i in range(1, len(parts) - 1, 2):
        idverse = parts[i]
        content = parts[i + 1]
        chunks.append((idverse, content))
    return chunks


def parse_verse_lines(verse_html: str) -> list[dict] | None:
    """
    Given the inner HTML of a <span class="verse"> element, return a list of
    {"t": str, "q": int} dicts, or None if there are no q-divs (prose verse).

    Structure expected:
        <span class="versenumber">N</span>
        [optional text before first div — this is the "first line"]
        <div class="verse_q2"> … </div>   ← optional
        <div class="verse_q1"> … </div>   ← optional
        …
    """
    q_divs = _Q_DIV_RE.findall(verse_html)
    if not q_divs:
        return None   # prose verse, no line structure

    # Remove the verse-number span so it doesn't bleed into the first-line text.
    body = re.sub(r'<span\s+class="versenumber"[^>]*>.*?</span>', "", verse_html, flags=re.DOTALL)

    # Remove all q-div blocks from body to isolate the pre-div text (first line).
    body_no_qdivs = _Q_DIV_RE.sub("", body)

    # Also strip footnote modals and cross-reference blocks that aren't verse text.
    body_no_qdivs = re.sub(r'<div[^>]*class="modal"[^>]*>.*?</div>', "", body_no_qdivs, flags=re.DOTALL)
    body_no_qdivs = re.sub(r'<a\b[^>]*>.*?</a>', "", body_no_qdivs, flags=re.DOTALL)

    first_line_text = _clean(body_no_qdivs)

    lines = []
    # The first-line indentation: look at the first q-div; if it's q2 the first
    # text is typically q1 (the "stem").  Default to q1.
    first_q = 1
    if q_divs and _q_level(q_divs[0][0]) == 2:
        first_q = 1
    elif q_divs:
        first_q = _q_level(q_divs[0][0])

    if first_line_text:
        lines.append({"t": first_line_text, "q": first_q})

    for cls, content in q_divs:
        text = _clean(content)
        if text:
            lines.append({"t": text, "q": _q_level(cls)})

    return lines if lines else None


# ---------------------------------------------------------------------------
# API fetch
# ---------------------------------------------------------------------------

def fetch_chapter_html(kitab: str, chapter: int, retries: int = 3) -> str | None:
    url = f"{BASE_URL}?edition=tb&kitab={kitab}&pasal={chapter}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = json.loads(resp.read())
                if data.get("success"):
                    return data["html"]
                return None
        except Exception as e:
            if attempt < retries - 1:
                wait = (attempt + 1) * 2
                print(f"    WARN {kitab}/{chapter} attempt {attempt+1}: {e} — retrying in {wait}s", file=sys.stderr)
                time.sleep(wait)
            else:
                print(f"    SKIP {kitab}/{chapter}: {e}", file=sys.stderr)
    return None


# ---------------------------------------------------------------------------
# Per-book processing
# ---------------------------------------------------------------------------

def process_book(
    slug: str,
    chapters: dict,
    dry_run: bool,
) -> tuple[int, int]:
    """Returns (chapters_processed, lines_added)."""
    kitab = SLUG_TO_KITAB[slug]
    total_lines = 0
    chapters_done = 0

    for ch_str, verses in sorted(chapters.items(), key=lambda x: int(x[0])):
        ch_num = int(ch_str)
        html = fetch_chapter_html(kitab, ch_num)
        if not html:
            time.sleep(DELAY)
            continue

        # Build idverse → parsed lines map
        verse_map: dict[str, list[dict]] = {}
        for idverse, verse_html in extract_verse_chunks(_strip_boilerplate(html)):
            parsed = parse_verse_lines(verse_html)
            if parsed:
                verse_map[idverse] = parsed

        lines_this = 0
        for verse in verses:
            # idverse format: e.g. "PSA1_3" = book + chapter + "_" + verse
            # We match by verse number suffix.
            vnum = verse["v"]
            # Find matching idverse (e.g. PSA1_3 for chapter 1 verse 3)
            key = next(
                (k for k in verse_map if k.endswith(f"_{vnum}") and f"{ch_num}_" in k),
                None
            )
            if key is None:
                continue

            new_lines = verse_map[key]
            if verse.get("lines") == new_lines:
                continue  # already up to date

            if not dry_run:
                verse["lines"] = new_lines
                # Also update the verse-level q from the first line
                verse["q"] = new_lines[0]["q"]

            lines_this += 1

        total_lines += lines_this
        chapters_done += 1
        if lines_this:
            print(f"    {slug} ch{ch_str}: {lines_this} verse(s) enriched"
                  f"{'  [dry]' if dry_run else ''}")
        time.sleep(DELAY)

    return chapters_done, total_lines


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _book_is_done(chapters: dict) -> bool:
    """Return True if every poetry verse in this book already has lines data."""
    for verses in chapters.values():
        for v in verses:
            if v.get("q") and not v.get("lines"):
                return False
    return True


def _save(seed: dict) -> None:
    with open(SEED_PATH, "w", encoding="utf-8") as f:
        json.dump(seed, f, ensure_ascii=False, separators=(",", ":"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Print changes without writing")
    parser.add_argument("--book", default=None,
                        help="Single book slug to process (e.g. mzm, yoh)")
    parser.add_argument("--resume", action="store_true",
                        help="Skip books that already look fully enriched")
    args = parser.parse_args()

    print(f"Loading {SEED_PATH} …")
    with open(SEED_PATH) as f:
        seed = json.load(f)

    books = seed["books"]
    target_slugs = [args.book] if args.book else list(books.keys())

    grand_ch = grand_lines = 0

    for slug in target_slugs:
        if slug in SKIP_SLUGS:
            print(f"Skip {slug} (deuterocanonical)")
            continue
        if slug not in SLUG_TO_KITAB:
            print(f"Skip {slug} (no kitab mapping)", file=sys.stderr)
            continue
        if args.resume and not args.dry_run and _book_is_done(books[slug]):
            print(f"Skip {slug} (already enriched)")
            continue

        print(f"\n=== {slug} → {SLUG_TO_KITAB[slug]} ===")
        chs, lines = process_book(slug, books[slug], dry_run=args.dry_run)
        grand_ch    += chs
        grand_lines += lines

        # Save after each book so a crash doesn't lose all progress
        if not args.dry_run and lines > 0:
            _save(seed)
            print(f"  → saved ({slug} done)")

    print(f"\nTotal: {grand_ch} chapters fetched, {grand_lines} verses enriched.")

    if not args.dry_run and grand_lines > 0:
        seed["seedVersion"] = seed.get("seedVersion", 0) + 1
        print(f"Bumping seedVersion → {seed['seedVersion']}")
        _save(seed)
        print("Final save done.")
    elif args.dry_run:
        print("Dry run — no files written.")
    else:
        print("Nothing to write.")


if __name__ == "__main__":
    main()
