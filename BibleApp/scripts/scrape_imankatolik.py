#!/usr/bin/env python3
"""
Scraper for https://www.imankatolik.or.id/alkitab.php

Fetches all 73 Catholic Bible books (Indonesian TB translation) and produces
a bible_seed.json compatible with BibleApp's BibleDatabase.

Usage:
    python3 scrape_imankatolik.py \\
        --output  ../generated/bible_seed_imankatolik.json \\
        --headings ../BibleApp/bible_seed.json \\
        --suspects ../generated/bible_seed.suspects.json \\
        --report  ../generated/heading_review.md \\
        [--resume]
"""

import argparse
import json
import re
import sys
import time
import datetime
from html import unescape
from pathlib import Path
from typing import Optional
from urllib.request import urlopen, Request
from urllib.error import URLError

# ---------------------------------------------------------------------------
# Book catalogue  (slug → site code, chapter count, display name)
# ---------------------------------------------------------------------------

# 7 books where the site's ?k= code differs from the app slug
_SLUG_OVERRIDE: dict[str, str] = {
    "ima": "im",
    "yol": "yl",
    "amo": "am",
    "oba": "ob",
    "mik": "mi",
    "zak": "za",
    "rom": "rm",
}

BOOKS: list[tuple[str, int, str]] = [
    # (slug, chapter_count, display_name)
    # Old Testament
    ("kej",  50, "Kejadian"),
    ("kel",  40, "Keluaran"),
    ("ima",  27, "Imamat"),
    ("bil",  36, "Bilangan"),
    ("ul",   34, "Ulangan"),
    ("yos",  24, "Yosua"),
    ("hak",  21, "Hakim-Hakim"),
    ("rut",   4, "Rut"),
    ("1sam", 31, "1 Samuel"),
    ("2sam", 24, "2 Samuel"),
    ("1raj", 22, "1 Raja-Raja"),
    ("2raj", 25, "2 Raja-Raja"),
    ("1taw", 29, "1 Tawarikh"),
    ("2taw", 36, "2 Tawarikh"),
    ("ezr",  10, "Ezra"),
    ("neh",  13, "Nehemia"),
    ("est",  10, "Ester"),
    ("ayb",  42, "Ayub"),
    ("mzm", 150, "Mazmur"),
    ("ams",  31, "Amsal"),
    ("pkh",  12, "Pengkhotbah"),
    ("kid",   8, "Kidung Agung"),
    ("yes",  66, "Yesaya"),
    ("yer",  52, "Yeremia"),
    ("rat",   5, "Ratapan"),
    ("yeh",  48, "Yehezkiel"),
    ("dan",  12, "Daniel"),
    ("hos",  14, "Hosea"),
    ("yol",   3, "Yoel"),
    ("amo",   9, "Amos"),
    ("oba",   1, "Obaja"),
    ("yun",   4, "Yunus"),
    ("mik",   7, "Mikha"),
    ("nah",   3, "Nahum"),
    ("hab",   3, "Habakuk"),
    ("zef",   3, "Zefanya"),
    ("hag",   2, "Hagai"),
    ("zak",  14, "Zakharia"),
    ("mal",   4, "Maleakhi"),
    # Deuterocanonical
    ("tob",  14, "Tobit"),
    ("ydt",  16, "Yudit"),
    ("1mak", 16, "1 Makabe"),
    ("2mak", 15, "2 Makabe"),
    ("keb",  19, "Kebijaksanaan"),
    ("sir",  51, "Sirakh"),
    ("bar",   6, "Barukh"),
    # New Testament
    ("mat",  28, "Matius"),
    ("mrk",  16, "Markus"),
    ("luk",  24, "Lukas"),
    ("yoh",  21, "Yohanes"),
    ("kis",  28, "Kisah Para Rasul"),
    ("rom",  16, "Roma"),
    ("1kor", 16, "1 Korintus"),
    ("2kor", 13, "2 Korintus"),
    ("gal",   6, "Galatia"),
    ("ef",    6, "Efesus"),
    ("flp",   4, "Filipi"),
    ("kol",   4, "Kolose"),
    ("1tes",  5, "1 Tesalonika"),
    ("2tes",  3, "2 Tesalonika"),
    ("1tim",  6, "1 Timotius"),
    ("2tim",  4, "2 Timotius"),
    ("tit",   3, "Titus"),
    ("flm",   1, "Filemon"),
    ("ibr",  13, "Ibrani"),
    ("yak",   5, "Yakobus"),
    ("1ptr",  5, "1 Petrus"),
    ("2ptr",  3, "2 Petrus"),
    ("1yoh",  5, "1 Yohanes"),
    ("2yoh",  1, "2 Yohanes"),
    ("3yoh",  1, "3 Yohanes"),
    ("yud",   1, "Yudas"),
    ("why",  22, "Wahyu"),
]

TOTAL_CHAPTERS = sum(ch for _, ch, _ in BOOKS)

# ---------------------------------------------------------------------------
# Fetching
# ---------------------------------------------------------------------------

BASE_URL = "https://www.imankatolik.or.id/alkitab.php"
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; BibleAppScraper/1.0)"}


def fetch_chapter(site_code: str, chapter: int, retries: int = 3) -> str:
    url = f"{BASE_URL}?k={site_code}&b={chapter}&a1=1&a2=999"
    for attempt in range(retries):
        try:
            req = Request(url, headers=_HEADERS)
            with urlopen(req, timeout=30) as resp:
                return resp.read().decode("utf-8", errors="replace")
        except URLError as e:
            if attempt < retries - 1:
                wait = 2 * (attempt + 1)
                print(f"    [retry {attempt+1}] {e} — waiting {wait}s", file=sys.stderr)
                time.sleep(wait)
            else:
                raise
    return ""  # unreachable


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

# Match the verse block between the justify div and the <hr>
_BLOCK_RE = re.compile(
    r'<div\s+style="text-align:justify">(.*?)<hr\s*/?>',
    re.DOTALL,
)
# Match each table row: <b>ABBREV&nbsp;CH:VNUM</b> ... text cell
_ROW_RE = re.compile(
    r'<td[^>]*class="v"[^>]*>\s*<b>[A-Za-z0-9]+(?:&nbsp;|\s)\d+:(\d+)</b>\s*</td>'
    r'\s*<td[^>]*class="v"[^>]*>(.*?)</td>',
    re.DOTALL,
)
# Strip all remaining HTML tags
_TAG_RE = re.compile(r"<[^>]+>")


def _clean_text(raw: str) -> str:
    text = _TAG_RE.sub("", raw)         # strip tags
    text = unescape(text)               # &amp; → & etc.
    text = re.sub(r"\s+", " ", text)    # collapse whitespace
    return text.strip()


def parse_verses(html: str) -> list[dict]:
    """Return list of {v: int, t: str} from a chapter page."""
    block_match = _BLOCK_RE.search(html)
    if not block_match:
        return []
    block = block_match.group(1)
    verses = []
    for m in _ROW_RE.finditer(block):
        v_num = int(m.group(1))
        text = _clean_text(m.group(2))
        if text:
            verses.append({"v": v_num, "t": text})
    return verses


# ---------------------------------------------------------------------------
# Heading overlay
# ---------------------------------------------------------------------------

def load_heading_map(path: Path) -> dict[tuple[str, str, int], str]:
    """Build a (slug, chapter_str, verse_num) → heading map from bible_seed.json."""
    data = json.loads(path.read_text(encoding="utf-8"))
    mapping: dict[tuple[str, str, int], str] = {}
    for slug, chapters in data.get("books", {}).items():
        for ch_str, verses in chapters.items():
            for verse in verses:
                h = verse.get("h")
                if h:
                    mapping[(slug, ch_str, verse["v"])] = h
    return mapping


def load_suspect_set(path: Optional[Path]) -> set[tuple[str, str, int]]:
    """Return set of (slug, chapter_str, verse_num) for suspect verses."""
    if path is None or not path.exists():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    return {(s["book"], s["chapter"], s["verse"]) for s in data}


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

_DEUTERO_SLUGS = {"tob", "ydt", "1mak", "2mak", "keb", "sir", "bar"}
_NO_HEADING_SLUGS = {"bar", "mrk", "flp", "kol", "flm", "2yoh", "3yoh", "yud"}

def write_report(
    report_path: Path,
    heading_map: dict[tuple[str, str, int], str],
    suspect_set: set[tuple[str, str, int]],
) -> None:
    slug_to_name = {slug: name for slug, _, name in BOOKS}
    lines: list[str] = []

    lines.append("# Heading Review Report\n")
    lines.append(f"Generated: {datetime.datetime.now().isoformat(timespec='seconds')}\n\n")

    # ── Section 1: Books with no headings ──────────────────────────────────
    lines.append("## Books with No Headings (need manual input)\n\n")
    lines.append("These books have zero headings in the current seed. ")
    lines.append("Please fill in the table from your physical Bible.\n\n")
    for slug, _, name in BOOKS:
        if slug in _NO_HEADING_SLUGS or slug in _DEUTERO_SLUGS:
            lines.append(f"### {name} (`{slug}`)\n\n")
            lines.append("| Chapter | Verse | Heading |\n")
            lines.append("|---------|-------|---------||\n")
            lines.append("| | | |\n\n")

    # ── Section 2: All existing headings ───────────────────────────────────
    lines.append("## All Existing Headings\n\n")
    lines.append("Scan against your physical Bible. ")
    lines.append("Rows marked ⚠️ are adjacent to OCR-suspect verses.\n\n")
    lines.append("| Book | Ch | V | Heading | Confidence |\n")
    lines.append("|------|----|---|---------|------------|\n")

    for slug, _, name in BOOKS:
        for (s, ch, v), heading in sorted(
            ((k, hv) for k, hv in heading_map.items() if k[0] == slug),
            key=lambda x: (int(x[0][1]), x[0][2]),
        ):
            # Flag if this verse OR the previous verse is a suspect
            is_suspect = (
                (slug, ch, v) in suspect_set
                or (slug, ch, v - 1) in suspect_set
            )
            flag = "⚠️ low confidence" if is_suspect else "✓"
            lines.append(f"| {name} | {ch} | {v} | {heading} | {flag} |\n")

    report_path.write_text("".join(lines), encoding="utf-8")
    print(f"Heading review report: {report_path}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape imankatolik.or.id Indonesian Bible")
    parser.add_argument("--output",   required=True, help="Path for output bible_seed JSON")
    parser.add_argument("--headings", help="Path to existing bible_seed.json (for heading overlay)")
    parser.add_argument("--suspects", help="Path to bible_seed.suspects.json (for confidence flags)")
    parser.add_argument("--report",   help="Path for heading review Markdown report")
    parser.add_argument("--resume",   action="store_true",
                        help="Skip books already present in --output (resume interrupted run)")
    parser.add_argument("--delay",    type=float, default=0.5,
                        help="Polite delay in seconds between requests (default: 0.5)")
    args = parser.parse_args()

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # Load heading overlay
    heading_map: dict[tuple[str, str, int], str] = {}
    if args.headings:
        h_path = Path(args.headings)
        if h_path.exists():
            heading_map = load_heading_map(h_path)
            print(f"Loaded {len(heading_map)} headings from {h_path}", file=sys.stderr)
        else:
            print(f"WARNING: --headings file not found: {h_path}", file=sys.stderr)

    # Load suspect set
    suspect_set = load_suspect_set(Path(args.suspects) if args.suspects else None)
    if suspect_set:
        print(f"Loaded {len(suspect_set)} suspect verse positions", file=sys.stderr)

    # Resume: load partial output
    result_books: dict[str, dict[str, list[dict]]] = {}
    if args.resume and out_path.exists():
        try:
            existing = json.loads(out_path.read_text(encoding="utf-8"))
            result_books = existing.get("books", {})
            print(f"Resuming: {len(result_books)} books already scraped", file=sys.stderr)
        except json.JSONDecodeError:
            print("WARNING: Could not parse existing output — starting fresh", file=sys.stderr)

    # Scrape
    done_chapters = 0
    for book_idx, (slug, chap_count, name) in enumerate(BOOKS):
        if slug in result_books:
            done_chapters += chap_count
            print(f"  skip {slug} (already scraped)", file=sys.stderr)
            continue

        site_code = _SLUG_OVERRIDE.get(slug, slug)
        book_data: dict[str, list[dict]] = {}

        for ch in range(1, chap_count + 1):
            done_chapters += 1
            pct = done_chapters / TOTAL_CHAPTERS * 100
            print(
                f"[{pct:5.1f}%] {name} {ch}/{chap_count}",
                end="\r",
                file=sys.stderr,
            )

            html = fetch_chapter(site_code, ch)
            verses = parse_verses(html)

            if not verses:
                print(
                    f"\nWARNING: no verses found for {slug} ch {ch} "
                    f"(url: ?k={site_code}&b={ch})",
                    file=sys.stderr,
                )

            # Overlay headings
            ch_str = str(ch)
            for verse in verses:
                h = heading_map.get((slug, ch_str, verse["v"]))
                if h:
                    verse["h"] = h

            book_data[ch_str] = verses
            time.sleep(args.delay)

        result_books[slug] = book_data
        print(f"\n  [{book_idx+1}/{len(BOOKS)}] {name}: done", file=sys.stderr)

        # Checkpoint after each book
        _write_output(out_path, result_books)

    # Final write
    _write_output(out_path, result_books)
    print(f"\nOutput: {out_path}", file=sys.stderr)

    # Heading report
    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        write_report(report_path, heading_map, suspect_set)


def _write_output(path: Path, books: dict) -> None:
    seed = {
        "version": "imankatolik",
        "seedVersion": 1,
        "books": books,
    }
    path.write_text(
        json.dumps(seed, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
