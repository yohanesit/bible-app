#!/usr/bin/env python3
"""
generate_lectionary_bundle.py

Fetches daily Catholic Mass lectionary citations from the cpbjr GitHub Pages API
and produces compact per-year JSON files for offline bundling in BibleApp.

Also scrapes Indonesian liturgical day names from imankatolik.or.id and stores
them in the `celebration` field of each BundledDay so the app can display the
proper Indonesian name (e.g. "HARI RAYA PASKAH", "Peringatan Wajib St. Antonius")
instead of the generic auto-generated "Weekday, Season" fallback.

Sources:
  Readings : https://cpbjr.github.io/catholic-readings-api/readings/{YEAR}/{MM-DD}.json
  Day names: https://imankatolik.or.id/kalender.php?b={month}&t={year}

Output format (one file per year, ~44 KB/year uncompressed):
  {
    "year": 2026,
    "generatedAt": "2026-04-20T00:00:00Z",
    "days": {
      "04-05": {
        "s": "Eastertide",
        "r": ["Acts 10:34a,37-43", "Psalm 118:1-2,16-17,22-23", null, "John 20:1-9"],
        "celebration": "HARI RAYA PASKAH (KEBANGKITAN TUHAN)"
      }
    }
  }

  "r" is always length-4: [firstReading, psalm, secondReading, gospel]
  null = absent reading (ferias have no secondReading)
  "celebration" is omitted when imankatolik returns a plain "Hari Biasa" (no added value)
  Dates absent from the output = API returned 404 (liturgical gap, e.g. Holy Saturday)

Usage:
    python3 scripts/generate_lectionary_bundle.py \\
        --years 2026 2027 2028 2029 2030 \\
        --output BibleApp/

    # Skip imankatolik scraping (readings-only, faster):
    python3 scripts/generate_lectionary_bundle.py --years 2026 --output BibleApp/ --skip-names
"""

import argparse
import calendar
import datetime
import json
import re
import sys
import time
from html.parser import HTMLParser
from pathlib import Path
from typing import Optional
from urllib.error import URLError
from urllib.request import Request, urlopen

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

CPBJR_BASE_URL   = "https://cpbjr.github.io/catholic-readings-api/readings"
IMANKAT_BASE_URL = "https://imankatolik.or.id/kalender.php"

_HEADERS = {"User-Agent": "BibleApp/1.0 (lectionary-bundle-generator)"}

CPBJR_DELAY   = 0.08   # seconds — polite for static GitHub Pages
IMANKAT_DELAY = 0.5    # seconds — be gentle with the smaller server

# Plain generic names from imankatolik that carry no more info than our
# auto-generated "Weekday, Season" fallback. These are skipped (celebration
# field omitted) so the app falls back to the richer auto-generated label.
_GENERIC_NAMES = {"hari biasa", "hari biasa."}


# ---------------------------------------------------------------------------
# imankatolik.or.id — HTML parser
# ---------------------------------------------------------------------------

class _ImankatParser(HTMLParser):
    """
    Extracts liturgical day names from imankatolik.or.id's calendar HTML.

    Each day is represented by two <a href="/kalender/{N}{Mon}.html"> anchors:
      - first anchor  → day number (digits only, ignored)
      - second anchor → liturgical name (what we want)
    """

    _HREF_RE = re.compile(r"/kalender/(\d+)[A-Za-z]+\.html", re.IGNORECASE)

    def __init__(self) -> None:
        super().__init__()
        self.day_names: dict[int, str] = {}   # {day_of_month: name}
        self._in_target = False
        self._current_day: Optional[int] = None
        self._buf: list[str] = []

    def handle_starttag(self, tag: str, attrs: list) -> None:
        if tag != "a":
            return
        href = dict(attrs).get("href", "")
        m = self._HREF_RE.search(href)
        if m:
            self._in_target = True
            self._current_day = int(m.group(1))
            self._buf = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._in_target:
            # Collapse internal newlines/multiple spaces → single space
            raw = " ".join("".join(self._buf).split())
            # Only store if text is a non-digit string (i.e. the name anchor, not the day-number anchor)
            if raw and not raw.isdigit() and self._current_day is not None:
                self.day_names[self._current_day] = raw
            self._in_target = False
            self._current_day = None
            self._buf = []

    def handle_data(self, data: str) -> None:
        if self._in_target:
            self._buf.append(data)

    def handle_entityref(self, name: str) -> None:
        _entities = {"amp": "&", "lt": "<", "gt": ">", "quot": '"', "nbsp": " "}
        if self._in_target:
            self._buf.append(_entities.get(name, ""))

    def handle_charref(self, name: str) -> None:
        if self._in_target:
            try:
                code = int(name[1:], 16) if name.startswith("x") else int(name)
                self._buf.append(chr(code))
            except (ValueError, OverflowError):
                pass


def fetch_imankat_month(year: int, month: int, retries: int = 3) -> dict[str, str]:
    """
    Scrape liturgical day names for one month from imankatolik.or.id.
    Returns dict mapping "MM-DD" → celebration name.
    Skips plain generic names that add no value over the auto-generated label.
    Returns an empty dict on failure (caller treats it as graceful degradation).
    """
    url = f"{IMANKAT_BASE_URL}?b={month}&t={year}"
    for attempt in range(retries):
        try:
            req = Request(url, headers=_HEADERS)
            with urlopen(req, timeout=20) as resp:
                raw_bytes = resp.read()
            # Detect encoding from headers; default to utf-8
            content_type = ""
            if hasattr(resp, "headers"):
                content_type = resp.headers.get("Content-Type", "")
            enc_match = re.search(r"charset=([\w-]+)", content_type, re.I)
            encoding = enc_match.group(1) if enc_match else "utf-8"
            html = raw_bytes.decode(encoding, errors="replace")

            parser = _ImankatParser()
            parser.feed(html)

            result: dict[str, str] = {}
            for day, name in parser.day_names.items():
                if name.lower().strip() not in _GENERIC_NAMES:
                    mmdd = f"{month:02d}-{day:02d}"
                    result[mmdd] = name
            return result

        except Exception as e:
            if attempt < retries - 1:
                wait = 1.5 * (attempt + 1)
                print(f"    [imankat retry {attempt + 1}] {e} — waiting {wait:.1f}s", file=sys.stderr)
                time.sleep(wait)
            else:
                print(f"    [imankat] Failed for {year}/{month:02d}: {e} — skipping names for this month", file=sys.stderr)
                return {}
    return {}


def fetch_imankat_year(year: int) -> dict[str, str]:
    """
    Scrape all 12 months from imankatolik.or.id for a given year.
    Returns combined dict mapping "MM-DD" → celebration name.
    """
    all_names: dict[str, str] = {}
    for month in range(1, 13):
        print(f"    [imankat] Fetching {year}/{month:02d}…", end=" ", file=sys.stderr)
        names = fetch_imankat_month(year, month)
        all_names.update(names)
        print(f"{len(names)} names", file=sys.stderr)
        time.sleep(IMANKAT_DELAY)
    return all_names


# ---------------------------------------------------------------------------
# cpbjr API — fetch readings
# ---------------------------------------------------------------------------

def fetch_day(year: int, mmdd: str, retries: int = 3) -> Optional[dict]:
    """
    Fetch a single day's lectionary reading citations from the cpbjr API.
    Returns the parsed JSON dict, or None if the date is not covered (404).
    Raises on network errors after retries.
    """
    url = f"{CPBJR_BASE_URL}/{year}/{mmdd}.json"
    for attempt in range(retries):
        try:
            req = Request(url, headers=_HEADERS)
            with urlopen(req, timeout=15) as resp:
                if resp.status == 200:
                    return json.loads(resp.read().decode("utf-8"))
                return None
        except URLError as e:
            if hasattr(e, "code") and e.code == 404:
                return None
            if attempt < retries - 1:
                wait = 1.5 * (attempt + 1)
                print(f"    [retry {attempt + 1}] {e} — waiting {wait:.1f}s", file=sys.stderr)
                time.sleep(wait)
            else:
                raise
    return None


# ---------------------------------------------------------------------------
# Transform
# ---------------------------------------------------------------------------

def to_bundled_day(raw: dict, celebration: Optional[str] = None) -> dict:
    """
    Convert a cpbjr API response to the compact BundledDay format.
    Optionally injects a `celebration` name from imankatolik.
    """
    readings = raw.get("readings") or {}
    r = [
        readings.get("firstReading") or None,
        readings.get("psalm") or None,
        readings.get("secondReading") or None,
        readings.get("gospel") or None,
    ]
    day: dict = {
        "s": raw.get("season") or "Ordinary Time",
        "r": r,
    }
    if celebration:
        day["celebration"] = celebration
    return day


# ---------------------------------------------------------------------------
# Generate one year
# ---------------------------------------------------------------------------

def generate_year(year: int, output_dir: Path, resume: bool, skip_names: bool) -> None:
    out_path = output_dir / f"lectionary_{year}.json"

    # Resume: load existing data
    existing_days: dict = {}
    if resume and out_path.exists():
        try:
            data = json.loads(out_path.read_text(encoding="utf-8"))
            existing_days = data.get("days", {})
            print(f"  Resuming {year}: {len(existing_days)} days already fetched", file=sys.stderr)
        except json.JSONDecodeError:
            print(f"  WARNING: Could not parse existing {out_path.name} — starting fresh", file=sys.stderr)

    # --- Step 1: Scrape Indonesian day names from imankatolik ---
    imankat_names: dict[str, str] = {}
    if not skip_names:
        print(f"  [{year}] Scraping day names from imankatolik.or.id…", file=sys.stderr)
        imankat_names = fetch_imankat_year(year)
        print(f"  [{year}] Got {len(imankat_names)} named days from imankatolik", file=sys.stderr)
    else:
        print(f"  [{year}] Skipping imankatolik scrape (--skip-names)", file=sys.stderr)

    # Merge freshly scraped names into existing days.
    # imankatolik name takes precedence; if absent, keep whatever was there before.
    days: dict = {}
    for mmdd, bundled in existing_days.items():
        entry = dict(bundled)
        name = imankat_names.get(mmdd)
        if name:
            entry["celebration"] = name
        days[mmdd] = entry

    # --- Step 2: Fetch readings from cpbjr API ---
    total_days = 366 if calendar.isleap(year) else 365
    done = 0
    skipped = 0
    gaps = 0

    date = datetime.date(year, 1, 1)
    end  = datetime.date(year + 1, 1, 1)

    while date < end:
        mmdd = date.strftime("%m-%d")
        done += 1

        if mmdd in existing_days:
            skipped += 1
            date += datetime.timedelta(days=1)
            continue

        pct = done / total_days * 100
        print(f"\r  [{year}] {pct:5.1f}%  {mmdd} …", end="", file=sys.stderr)

        try:
            raw = fetch_day(year, mmdd)
        except Exception as e:
            print(f"\n  ERROR fetching {year}/{mmdd}: {e}", file=sys.stderr)
            raw = None

        if raw is not None:
            celebration = imankat_names.get(mmdd)
            days[mmdd] = to_bundled_day(raw, celebration=celebration)
        else:
            gaps += 1  # 404 = liturgical gap, intentionally omitted

        time.sleep(CPBJR_DELAY)
        date += datetime.timedelta(days=1)

    # Write output
    bundle = {
        "year": year,
        "generatedAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "days": dict(sorted(days.items())),
    }
    out_path.write_text(
        json.dumps(bundle, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    covered = len(days)
    named   = sum(1 for d in days.values() if d.get("celebration"))
    print(
        f"\r  [{year}] done — {covered} days covered, {named} with Indonesian names, "
        f"{gaps} liturgical gaps, {skipped} skipped (resume)                    ",
        file=sys.stderr,
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate offline lectionary bundle JSON files for BibleApp"
    )
    parser.add_argument(
        "--years", nargs="+", type=int, required=True,
        help="Calendar years to generate (e.g. --years 2026 2027 2028)"
    )
    parser.add_argument(
        "--output", default="BibleApp/",
        help="Output directory for lectionary_YYYY.json files (default: BibleApp/)"
    )
    parser.add_argument(
        "--resume", action="store_true",
        help="Skip dates already present in existing output files (re-enriches celebration names)"
    )
    parser.add_argument(
        "--skip-names", action="store_true",
        help="Skip scraping imankatolik.or.id — produce readings-only bundle"
    )
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Generating lectionary data for years: {args.years}", file=sys.stderr)
    print(f"Output directory: {output_dir.resolve()}", file=sys.stderr)
    print(f"cpbjr delay: {CPBJR_DELAY}s | imankat delay: {IMANKAT_DELAY}s", file=sys.stderr)
    print("", file=sys.stderr)

    for year in args.years:
        generate_year(year, output_dir, resume=args.resume, skip_names=args.skip_names)

    print("\nDone.", file=sys.stderr)


if __name__ == "__main__":
    main()
