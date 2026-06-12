#!/usr/bin/env python3
"""
Scrapes section headings from alkitab.mobi (TB) and writes them
into the h field of bible_seed.json.

Usage:
    python3 enrich_headings.py [--dry-run] [--book <slug>]

Options:
    --dry-run   Print changes without writing
    --book      Only process a single book slug (e.g. yoh)
"""

import argparse
import json
import re
import time
import sys
from pathlib import Path
import urllib.request
import urllib.error

SEED_PATH = Path(__file__).parent.parent / "BibleApp/BibleApp/bible_seed.json"
BASE_URL = "https://alkitab.mobi/tb"
DELAY = 0.5  # seconds between requests, be polite

# Our slug → alkitab.mobi URL segment.
# Pattern is title-case of our slug, with two exceptions:
#   yol → Yoel  (our abbreviation differs from their URL)
# Deuterocanonical books absent from TB are listed in SKIP_SLUGS.
SLUG_MAP: dict[str, str] = {
    # Pentateuch
    "kej": "Kej", "kel": "Kel", "ima": "Ima", "bil": "Bil", "ul": "Ul",
    # History
    "yos": "Yos", "hak": "Hak", "rut": "Rut",
    "1sam": "1Sam", "2sam": "2Sam",
    "1raj": "1Raj", "2raj": "2Raj",
    "1taw": "1Taw", "2taw": "2Taw",
    "ezr": "Ezr", "neh": "Neh", "est": "Est",
    # Wisdom / Poetry
    "ayb": "Ayb", "mzm": "Mzm", "ams": "Ams",
    "pkh": "Pkh", "kid": "Kid",
    # Major Prophets
    "yes": "Yes", "yer": "Yer", "rat": "Rat", "yeh": "Yeh", "dan": "Dan",
    # Minor Prophets
    "hos": "Hos", "yol": "Yoel", "amo": "Amo", "oba": "Oba",
    "yun": "Yun", "mik": "Mik", "nah": "Nah", "hab": "Hab",
    "zef": "Zef", "hag": "Hag", "zak": "Zak", "mal": "Mal",
    # Gospels & Acts
    "mat": "Mat", "mrk": "Mrk", "luk": "Luk", "yoh": "Yoh", "kis": "Kis",
    # Pauline letters
    "rom": "Rom",
    "1kor": "1Kor", "2kor": "2Kor",
    "gal": "Gal", "ef": "Ef", "flp": "Flp", "kol": "Kol",
    "1tes": "1Tes", "2tes": "2Tes",
    "1tim": "1Tim", "2tim": "2Tim",
    "tit": "Tit", "flm": "Flm",
    # General letters
    "ibr": "Ibr", "yak": "Yak",
    "1ptr": "1Ptr", "2ptr": "2Ptr",
    "1yoh": "1Yoh", "2yoh": "2Yoh", "3yoh": "3Yoh",
    "yud": "Yud",
    # Revelation
    "why": "Why",
}

# Deuterocanonical books — not in TB, skip silently.
SKIP_SLUGS = {"tob", "ydt", "1mak", "2mak", "keb", "sir", "bar"}


def fetch_html(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")


def extract_headings(html: str) -> dict[int, str]:
    """
    Returns {verse_number: heading_text} for all section headings in a chapter.
    The heading is attached to the first verse that follows it.
    """
    passage_match = re.search(
        r'<div[^>]+id="passage-text"[^>]*>(.*?)</div>', html, re.DOTALL
    )
    if not passage_match:
        return {}

    p_tags = re.findall(r"<p[^>]*>.*?</p>", passage_match.group(1), re.DOTALL)

    headings: dict[int, str] = {}
    pending_title: str | None = None

    for p in p_tags:
        classes = re.findall(r'class="([^"]+)"', p)
        flat_class = " ".join(classes)
        text = re.sub(r"<[^>]+>", "", p).strip()

        if "paragraphtitle" in flat_class:
            pending_title = text
        elif "reftext" in flat_class and pending_title:
            # Extract verse number from the first anchor/text in the tag
            verse_match = re.search(r">(\d+)<", p)
            if verse_match:
                verse_num = int(verse_match.group(1))
                # Only attach if not already claimed by a closer heading
                if verse_num not in headings:
                    headings[verse_num] = pending_title
            pending_title = None

    return headings


def process_book(slug: str, chapters: dict, dry_run: bool) -> tuple[int, int]:
    """Returns (chapters_processed, headings_added)."""
    mobi_slug = SLUG_MAP.get(slug)
    if not mobi_slug:
        return 0, 0

    total_added = 0
    chapters_done = 0

    for ch_str, verses in sorted(chapters.items(), key=lambda x: int(x[0])):
        url = f"{BASE_URL}/{mobi_slug}/{ch_str}"
        try:
            html = fetch_html(url)
        except Exception as e:
            print(f"  WARN {slug} {ch_str}: {e}", file=sys.stderr)
            time.sleep(DELAY)
            continue

        headings = extract_headings(html)
        added_this_chapter = 0

        for verse in verses:
            v_num = verse["v"]
            if v_num in headings:
                new_heading = headings[v_num]
                old_heading = verse.get("h")
                if old_heading != new_heading:
                    if not dry_run:
                        verse["h"] = new_heading
                    else:
                        print(
                            f"  [DRY] {slug} {ch_str}:{v_num}  "
                            f'"{old_heading}" → "{new_heading}"'
                        )
                    added_this_chapter += 1

        total_added += added_this_chapter
        chapters_done += 1
        print(
            f"  {slug} ch{ch_str}: {added_this_chapter} heading(s) "
            f"({'dry' if dry_run else 'written'})"
        )
        time.sleep(DELAY)

    return chapters_done, total_added


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--book", default=None, help="Single book slug to process")
    args = parser.parse_args()

    print(f"Loading {SEED_PATH} …")
    with open(SEED_PATH) as f:
        seed = json.load(f)

    books = seed["books"]
    target_slugs = [args.book] if args.book else list(books.keys())

    total_chapters = 0
    total_headings = 0

    for slug in target_slugs:
        if slug in SKIP_SLUGS:
            print(f"Skip {slug} (deuterocanonical, not in TB)")
            continue
        if slug not in SLUG_MAP:
            print(f"Skip {slug} (no URL mapping defined)", file=sys.stderr)
            continue

        print(f"\n=== {slug} → {SLUG_MAP[slug]} ===")
        chs, hs = process_book(slug, books[slug], dry_run=args.dry_run)
        total_chapters += chs
        total_headings += hs

    print(
        f"\nDone. {total_chapters} chapters processed, "
        f"{total_headings} heading(s) {'would be ' if args.dry_run else ''}added."
    )

    if not args.dry_run and total_headings > 0:
        print(f"Writing {SEED_PATH} …")
        with open(SEED_PATH, "w") as f:
            json.dump(seed, f, ensure_ascii=False, separators=(",", ":"))
        print("Saved.")


if __name__ == "__main__":
    main()
