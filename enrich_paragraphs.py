#!/usr/bin/env python3
"""
Reads paragraph-break (p) and poetry-indentation (q) data from USFM source
files and injects them into bible_seed.json.

Sources (both freely available from eBible.org):
  • TSI  — Terjemahan Sederhana Indonesia (ind_usfm.zip)  ← preferred; same
            paragraph/poetry structure as TB because both follow the same
            underlying Hebrew/Greek text divisions.
  • WEB  — World English Bible (eng-web_usfm.zip)         ← fallback for the
            ~18 OT books not yet in TSI (Psalms, Job, Jeremiah, Ezekiel, etc.)

What the script writes:
  "p": true   on the first verse of every new prose paragraph  (\\p marker)
  "q": 1|2    on every poetry verse, indicating its USFM indentation level
              (\\q1 = base poetry line, \\q2 = indented continuation line)

Usage:
    python3 enrich_paragraphs.py [--dry-run] [--book <slug>]

Options:
    --dry-run   Print proposed changes without writing anything
    --book      Only process a single book slug (e.g. mzm, yoh)
"""

import argparse
import io
import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SEED_PATH  = Path(__file__).parent / "BibleApp/BibleApp/bible_seed.json"
CACHE_DIR  = Path(__file__).parent / ".usfm_cache"

TSI_URL    = "https://ebible.org/Scriptures/ind_usfm.zip"
WEB_URL    = "https://ebible.org/Scriptures/eng-web_usfm.zip"

# ---------------------------------------------------------------------------
# Slug → USFM filename stem  (TSI preferred, WEB fallback)
# ---------------------------------------------------------------------------

# TSI books (files named like "02-GENind.usfm")
TSI_MAP: dict[str, str] = {
    "kej":  "02-GENind",  "kel":  "03-EXOind",  "ima":  "04-LEVind",
    "bil":  "05-NUMind",  "ul":   "06-DEUind",  "yos":  "07-JOSind",
    "hak":  "08-JDGind",  "rut":  "09-RUTind",  "1sam": "10-1SAind",
    "2sam": "11-2SAind",  "1raj": "12-1KIind",  "2raj": "13-2KIind",
    "ezr":  "16-EZRind",  "neh":  "17-NEHind",  "est":  "18-ESTind",
    "ams":  "21-PROind",  "pkh":  "22-ECCind",  "yes":  "24-ISAind",
    "yun":  "33-JONind",  "zak":  "39-ZECind",  "mal":  "40-MALind",
    "mat":  "46-MATind",  "mrk":  "47-MRKind",  "luk":  "48-LUKind",
    "yoh":  "49-JHNind",  "kis":  "50-ACTind",  "rom":  "51-ROMind",
    "1kor": "52-1COind",  "2kor": "77-2COind",  "gal":  "54-GALind",
    "ef":   "55-EPHind",  "flp":  "56-PHPind",  "kol":  "57-COLind",
    "1tes": "58-1THind",  "2tes": "59-2THind",  "1tim": "60-1TIind",
    "2tim": "85-2TIind",  "tit":  "62-TITind",  "flm":  "63-PHMind",
    "ibr":  "64-HEBind",  "yak":  "65-JASind",  "1ptr": "66-1PEind",
    "2ptr": "67-2PEind",  "1yoh": "68-1JNind",  "2yoh": "69-2JNind",
    "3yoh": "70-3JNind",  "yud":  "71-JUDind",  "why":  "72-REVind",
}

# WEB fallback books (files named like "14-1CHeng-web.usfm")
WEB_MAP: dict[str, str] = {
    "1taw": "14-1CHeng-web",  "2taw": "15-2CHeng-web",
    "ayb":  "19-JOBeng-web",  "mzm":  "20-PSAeng-web",
    "kid":  "23-SNGeng-web",  "yer":  "25-JEReng-web",
    "rat":  "26-LAMeng-web",  "yeh":  "27-EZKeng-web",
    "dan":  "28-DANeng-web",  "hos":  "29-HOSeng-web",
    "yol":  "30-JOLeng-web",  "amo":  "31-AMOeng-web",
    "oba":  "32-OBAeng-web",  "mik":  "34-MICeng-web",
    "nah":  "35-NAHeng-web",  "hab":  "36-HABeng-web",
    "zef":  "37-ZEPeng-web",  "hag":  "38-HAGeng-web",
}

# Deuterocanonical books not in TB — skip silently
SKIP_SLUGS = {"tob", "ydt", "1mak", "2mak", "keb", "sir", "bar"}

# ---------------------------------------------------------------------------
# USFM zip download / cache
# ---------------------------------------------------------------------------

def get_zip(url: str, label: str) -> zipfile.ZipFile:
    CACHE_DIR.mkdir(exist_ok=True)
    fname = CACHE_DIR / Path(url).name
    if not fname.exists():
        print(f"  Downloading {label} …", end=" ", flush=True)
        urllib.request.urlretrieve(url, fname)
        print("done")
    return zipfile.ZipFile(fname)


# ---------------------------------------------------------------------------
# USFM paragraph/poetry parser
# ---------------------------------------------------------------------------

# Markers that trigger a new prose paragraph
_PARA_MARKERS = re.compile(r"^\\(m|mi|p|pi\d?|pc|pr|cls|pmo|pm|pmc|pmr)\b")

# Poetry markers: \q, \q1, \q2, \q3, \qr, \qc, \qa, \qm, \qm1, \qm2
_POETRY_MARKER = re.compile(r"^\\q([mr]?\d?)\b")

# \v NNN  (also handles ranges like 14-15 → takes the first number)
_VERSE_RE = re.compile(r"^\\v\s+(\d+)")

# \c NNN
_CHAPTER_RE = re.compile(r"^\\c\s+(\d+)")

# Strip USFM inline markup  (\w word\w*, \f … \f*, etc.) from text
_INLINE_RE = re.compile(r"\\[a-z+*]+\s*(?:\*)?")


def _q_level(marker_line: str) -> int:
    """Return numeric q-level from a \\q marker line (default 1)."""
    m = _POETRY_MARKER.match(marker_line)
    if not m:
        return 1
    suffix = m.group(1).strip()
    if suffix.isdigit():
        return int(suffix)
    return 1


def parse_usfm(content: str) -> dict[int, dict[int, dict]]:
    """
    Parse USFM text.

    Returns:
        { chapter_int: { verse_int: { "p": bool, "q": int|None } } }

    "p" = True if a \\p marker preceded this verse (new paragraph).
    "q" = 1 or 2 if a \\q1/\\q2 marker preceded this verse; None for prose.
    """
    result: dict[int, dict[int, dict]] = {}
    current_chapter = 0
    pending_p = False   # saw a \p marker, waiting for next \v
    pending_q: int | None = None  # saw a \q marker; value = level

    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        # Chapter boundary
        cm = _CHAPTER_RE.match(line)
        if cm:
            current_chapter = int(cm.group(1))
            result.setdefault(current_chapter, {})
            pending_p = False
            pending_q = None
            continue

        # Prose paragraph marker
        if _PARA_MARKERS.match(line):
            pending_p = True
            pending_q = None   # \p cancels any pending \q
            continue

        # Poetry marker (possibly with trailing text — a continuation line)
        if _POETRY_MARKER.match(line):
            level = _q_level(line)
            # If the marker line itself contains a \v, handle below;
            # otherwise just record the pending level.
            if "\\v" not in line:
                pending_q = level
                pending_p = False  # \q cancels pending \p
            continue

        # Verse marker
        vm = _VERSE_RE.match(line)
        if vm and current_chapter:
            verse_num = int(vm.group(1))
            result[current_chapter][verse_num] = {
                "p": pending_p,
                "q": pending_q,
            }
            # Only the FIRST verse after \p / \q consumes the flag
            pending_p = False
            pending_q = None
            continue

    return result


# ---------------------------------------------------------------------------
# Main processing
# ---------------------------------------------------------------------------

def process_book(
    slug: str,
    chapters: dict,
    tsi_zip: zipfile.ZipFile,
    web_zip: zipfile.ZipFile,
    dry_run: bool,
) -> tuple[int, int, int]:
    """Returns (chapters_processed, p_added, q_added)."""

    # Pick source
    if slug in TSI_MAP:
        fname = TSI_MAP[slug] + ".usfm"
        src_zip, label = tsi_zip, "TSI"
    elif slug in WEB_MAP:
        fname = WEB_MAP[slug] + ".usfm"
        src_zip, label = web_zip, "WEB"
    else:
        return 0, 0, 0

    try:
        raw = src_zip.read(fname).decode("utf-8", errors="replace")
    except KeyError:
        print(f"  WARN {slug}: {fname} not found in zip", file=sys.stderr)
        return 0, 0, 0

    usfm_data = parse_usfm(raw)

    total_p = total_q = chapters_done = 0

    for ch_str, verses in sorted(chapters.items(), key=lambda x: int(x[0])):
        ch_num = int(ch_str)
        ch_data = usfm_data.get(ch_num, {})
        p_this = q_this = 0

        for verse in verses:
            vnum = verse["v"]
            info = ch_data.get(vnum, {})

            # --- paragraph break ---
            want_p = bool(info.get("p"))
            if want_p and verse.get("p") != True:
                if not dry_run:
                    verse["p"] = True
                p_this += 1

            # --- poetry level ---
            want_q = info.get("q")   # int 1/2 or None
            if want_q and verse.get("q") != want_q:
                if not dry_run:
                    verse["q"] = want_q
                q_this += 1

        if dry_run and (p_this or q_this):
            print(f"    [DRY] {slug} ch{ch_str}: {p_this} p, {q_this} q")

        total_p += p_this
        total_q += q_this
        chapters_done += 1

    print(
        f"  {slug} ({label}): {chapters_done} chapters, "
        f"{total_p} paragraph breaks, {total_q} poetry verses"
        f"{'  [dry]' if dry_run else ''}"
    )
    return chapters_done, total_p, total_q


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Print changes without writing")
    parser.add_argument("--book", default=None,
                        help="Single book slug to process (e.g. mzm, yoh)")
    args = parser.parse_args()

    print(f"Loading {SEED_PATH} …")
    with open(SEED_PATH) as f:
        seed = json.load(f)

    books = seed["books"]
    target_slugs = [args.book] if args.book else list(books.keys())

    print("Fetching USFM sources …")
    tsi_zip = get_zip(TSI_URL, "TSI")
    web_zip = get_zip(WEB_URL, "WEB")

    grand_p = grand_q = grand_ch = 0

    for slug in target_slugs:
        if slug in SKIP_SLUGS:
            print(f"Skip {slug} (deuterocanonical)")
            continue
        if slug not in TSI_MAP and slug not in WEB_MAP:
            print(f"Skip {slug} (no USFM source mapped)", file=sys.stderr)
            continue

        chs, ps, qs = process_book(
            slug, books[slug], tsi_zip, web_zip, dry_run=args.dry_run
        )
        grand_ch += chs
        grand_p  += ps
        grand_q  += qs

    tsi_zip.close()
    web_zip.close()

    print(
        f"\nTotal: {grand_ch} chapters, "
        f"{grand_p} paragraph breaks, {grand_q} poetry verses."
    )

    if not args.dry_run and (grand_p + grand_q) > 0:
        # Bump seedVersion so installed apps reload the enriched seed
        seed["seedVersion"] = seed.get("seedVersion", 0) + 1
        print(f"Bumping seedVersion → {seed['seedVersion']}")
        print(f"Writing {SEED_PATH} …")
        with open(SEED_PATH, "w", encoding="utf-8") as f:
            json.dump(seed, f, ensure_ascii=False, separators=(",", ":"))
        print("Saved.")
    elif args.dry_run:
        print("Dry run — no files written.")
    else:
        print("Nothing to write (no changes detected).")


if __name__ == "__main__":
    main()
