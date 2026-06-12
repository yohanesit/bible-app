#!/usr/bin/env python3
"""
Offline PDF → Bible JSON converter for BibleApp.

Input:
  - A PDF whose extracted text looks like LAI TB Deuterokanonika
    (book headers, chapter numbers at chapter start, and verse numbers inline).

Output (matches BibleDatabase.swift):
  - <out_dir>/<slug>.json for each parsed book, shaped as:
      { "1": [ {"v":1,"t":"..."}, ... ], "2": [ ... ] }
  - Optionally, a single bible_seed.json file in the bundle seed format:
      { "version":"tb", "generatedAt":"...", "books": { "<slug>": <bookData> } }

Notes:
  - This script is purely mechanical. Make sure you have the right to
    distribute the underlying text.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


# ---- Catalog parsing (avoid duplicating book list) ----

@dataclass(frozen=True)
class CatalogEntry:
    slug: str
    name: str
    chapter_count: int


_CATALOG_ENTRY_RE = re.compile(
    r"""\.init\(\s*slug:\s*"(?P<slug>[^"]+)"\s*,\s*name:\s*"(?P<name>[^"]+)"[^)]*chapterCount:\s*(?P<count>\d+)""",
    re.UNICODE,
)


def load_catalog_from_swift(bible_catalog_swift: Path) -> Dict[str, CatalogEntry]:
    """
    Returns mapping of normalized uppercase book display name → CatalogEntry.
    Normalization aims to match the PDF's uppercase book headers.
    """
    text = bible_catalog_swift.read_text(encoding="utf-8")
    entries: List[CatalogEntry] = []
    for m in _CATALOG_ENTRY_RE.finditer(text):
        entries.append(
            CatalogEntry(
                slug=m.group("slug"),
                name=m.group("name"),
                chapter_count=int(m.group("count")),
            )
        )

    def norm_book_name(s: str) -> str:
        # Match PDF headers like "HAKIM-HAKIM" vs catalog "Hakim-Hakim".
        s = s.upper()
        # Fold diacritics (e.g. "YOËL" → "YOEL") so matching is robust.
        s = "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))
        s = s.replace("—", "-")
        s = re.sub(r"\s+", " ", s).strip()
        return s

    def add_alias(alias: str, entry: CatalogEntry) -> None:
        mapping[norm_book_name(alias)] = entry
        mapping[norm_book_name(alias.replace("-", " "))] = entry
        mapping[re.sub(r"\s+", "", norm_book_name(alias))] = entry

    # Provide a few aliases for common header variants.
    mapping: Dict[str, CatalogEntry] = {}
    for e in entries:
        add_alias(e.name, e)

    # Numeral books sometimes show without space ("1SAMUEL") or with dot ("1. SAMUEL")
    for e in entries:
        n = norm_book_name(e.name)
        mapping[re.sub(r"\s+", "", n)] = e
        mapping[re.sub(r"^(\d)\s+", r"\1 ", n)] = e
        mapping[re.sub(r"^(\d)\s+", r"\1. ", n)] = e

    # Extra aliases for common Indonesian headers/footers in TB PDFs.
    # Gospels often appear as "INJIL MATIUS", etc.
    gospel_prefix = "INJIL "
    for e in entries:
        if e.slug in {"mat", "mrk", "luk", "yoh"}:
            add_alias(gospel_prefix + e.name, e)

    # Letters often use long titles in footers.
    slug_to_long: Dict[str, str] = {
        "rom": "SURAT PAULUS KEPADA JEMAAT DI ROMA",
        "1kor": "SURAT PAULUS YANG PERTAMA KEPADA JEMAAT DI KORINTUS",
        "2kor": "SURAT PAULUS YANG KEDUA KEPADA JEMAAT DI KORINTUS",
        "gal": "SURAT PAULUS KEPADA JEMAAT DI GALATIA",
        "ef": "SURAT PAULUS KEPADA JEMAAT DI EFESUS",
        "flp": "SURAT PAULUS KEPADA JEMAAT DI FILIPI",
        "kol": "SURAT PAULUS KEPADA JEMAAT DI KOLOSE",
        "1tes": "SURAT PAULUS YANG PERTAMA KEPADA JEMAAT DI TESALONIKA",
        "2tes": "SURAT PAULUS YANG KEDUA KEPADA JEMAAT DI TESALONIKA",
        "1tim": "SURAT PAULUS YANG PERTAMA KEPADA TIMOTIUS",
        "2tim": "SURAT PAULUS YANG KEDUA KEPADA TIMOTIUS",
        "tit": "SURAT PAULUS KEPADA TITUS",
        "flm": "SURAT PAULUS KEPADA FILEMON",
        "ibr": "SURAT KEPADA ORANG IBRANI",
        "yak": "SURAT YAKOBUS",
        "1ptr": "SURAT PETRUS YANG PERTAMA",
        "2ptr": "SURAT PETRUS YANG KEDUA",
        "1yoh": "SURAT YOHANES YANG PERTAMA",
        "2yoh": "SURAT YOHANES YANG KEDUA",
        "3yoh": "SURAT YOHANES YANG KETIGA",
        "yud": "SURAT YUDAS",
        "why": "WAHYU KEPADA YOHANES",
    }
    by_slug = {e.slug: e for e in entries}
    for slug, long_title in slug_to_long.items():
        e = by_slug.get(slug)
        if e:
            add_alias(long_title, e)

    # Deuterocanonical / alternate Indonesian headings commonly used in PDFs
    # (e.g. TOC uses "Yesus bin Sirakh")
    extra_aliases: Dict[str, str] = {
        "YESUS BIN SIRAKH": "sir",
        "YESUS BIN SIRAK": "sir",
        "KITAB YESUS BIN SIRAKH": "sir",
        # Running-header abbreviation used in this PDF: "SIRAKH 15, 16 [73]"
        "SIRAKH": "sir",
        "BARUKH": "bar",
        "BARUK": "bar",
        "KITAB BARUKH": "bar",
        "OBADJA": "oba",
        "OBADIA": "oba",
        "KITAB OBADJA": "oba",
        "KITAB OBAJA": "oba",
        "MALEAKI": "mal",
        "MALAKHI": "mal",
        "MALEAKHI": "mal",
        "KITAB MALEAKI": "mal",
        "KITAB MALEAKHI": "mal",
        "RUTH": "rut",
        "KITAB RUT": "rut",
        "RUT": "rut",
        "OBAJA": "oba",
        "YUDAS": "yud",
        "KITAB YUDAS": "yud",
        "SURAT YUDAS": "yud",
        "I YOHANES": "1yoh",
        "II YOHANES": "2yoh",
        "III YOHANES": "3yoh",
        "I MAKABE": "1mak",
        "II MAKABE": "2mak",
        "KITAB I MAKABE": "1mak",
        "KITAB II MAKABE": "2mak",
        "II TESALONIKA": "2tes",
        "SURAT PAULUS YANG KEDUA KEPADA JEMAAT DI TESALONIKA": "2tes",
        "SURAT PAULUS KEPADA FILEMON": "flm",
        # Running-header abbreviation for Wisdom of Solomon: "KEB. SALOMO 1 [35]"
        "KEB. SALOMO": "keb",
        "KEB SALOMO": "keb",
    }
    for alias, slug in extra_aliases.items():
        e = by_slug.get(slug)
        if e:
            add_alias(alias, e)

    return mapping


# ---- PDF extraction ----

def _extract_column_text_pdfplumber(col_page: object, *, add_sentinel: bool = True) -> str:  # type: ignore[return]
    """
    Extract text from a single pdfplumber page crop (one column).

    This PDF uses space characters as syllable separators (e.g. the word
    "melahirkan" is stored as "me <sp> la <sp> h <sp> ir <sp> kan"). Both
    syllable-spaces and real word-spaces have nearly identical widths (~2.2 pt),
    so the only reliable discriminator is the *cross-space gap*: the distance
    from the previous character's right edge to the next character's left edge.
    Within a word this gap is < 1 pt; between words it is ~2 pt.

    When *add_sentinel* is False (used for the running-header crop) the large-font
    digit sentinel (\\x02) is suppressed.  Running headers are only used for book
    and chapter *detection*; they must never trigger chapter-start logic in the
    parser, which processes the full page text.
    """
    chars = col_page.chars  # type: ignore[attr-defined]
    if not chars:
        return ""

    # Sort into visual reading order: (line-bucket, x, spaces-before-letters).
    # Spaces must precede same-x chars so look-ahead for the next char is correct.
    chars = sorted(
        chars,
        key=lambda c: (round(c["top"] / 2) * 2, c["x0"], 0 if c["text"] == " " else 1),
    )

    filtered: List[object] = []
    i = 0
    while i < len(chars):
        c = chars[i]
        if c["text"] == " ":  # type: ignore[index]
            # Previous non-space char (already in filtered)
            prev_char = None
            for k in range(len(filtered) - 1, -1, -1):
                if filtered[k]["text"] != " ":  # type: ignore[index]
                    prev_char = filtered[k]
                    break
            # Next non-space char on the same line
            j = i + 1
            while j < len(chars) and chars[j]["text"] == " ":  # type: ignore[index]
                j += 1
            next_char = None
            if j < len(chars) and abs(chars[j]["top"] - c["top"]) <= 3:  # type: ignore[index]
                next_char = chars[j]

            if prev_char is not None and next_char is not None:
                gap = next_char["x0"] - prev_char["x1"]  # type: ignore[index]
                if gap < 1.0:
                    i += 1
                    continue  # syllable-level space — skip
        filtered.append(c)
        i += 1

    # Group chars into lines by top coordinate (tolerance 3 pt).
    lines: List[List[object]] = []
    cur_line: List[object] = [filtered[0]] if filtered else []
    for c in filtered[1:]:
        if abs(c["top"] - cur_line[-1]["top"]) <= 3:  # type: ignore[index]
            cur_line.append(c)
        else:
            lines.append(cur_line)
            cur_line = [c]
    if cur_line:
        lines.append(cur_line)

    # Compute typical line spacing (median gap between consecutive lines).
    tops = [min(c["top"] for c in ln) for ln in lines]  # type: ignore[index]
    gaps = [tops[i + 1] - tops[i] for i in range(len(tops) - 1)]
    if gaps:
        sorted_gaps = sorted(g for g in gaps if 2 < g < 30)
        normal_spacing = sorted_gaps[len(sorted_gaps) // 2] if sorted_gaps else 10.0
    else:
        normal_spacing = 10.0

    # Build result, inserting a blank line wherever the gap exceeds 1.4× normal
    # spacing (paragraph / chapter break) so that `prev_blank` fires in the parser.
    #
    # Also tag lines whose first non-space character is a digit with large font
    # size (≥ 12 pt) with a sentinel \x02.  Chapter numbers in this Bible are
    # printed bold at ~20 pt; inline verse-number superscripts are ~6 pt.  The
    # sentinel lets the parser distinguish "14 Pada zaman Amrafel…" (chapter 14)
    # from "14 Setelah Lot berpisah…" (verse 14 within a chapter).
    CHAPTER_NUM_SIZE_THRESHOLD = 12.0
    result = []
    for i, line in enumerate(lines):
        if i > 0 and gaps[i - 1] > normal_spacing * 1.4:
            result.append("")
        sorted_line = sorted(line, key=lambda c: c["x0"])  # type: ignore[index]
        text = "".join(c["text"] for c in sorted_line)
        text = text.strip()
        if text:
            sig_chars = [c for c in sorted_line if c["text"].strip()]  # type: ignore[index]
            # Allow a single leading hyphen (hanging-hyphen artefact from the
            # previous column's last word).  E.g. "-4  Saudara-saudaraku…"
            # should still be recognised as a chapter-4 sentinel.
            first_char = sig_chars[0] if sig_chars else None
            strip_leading_hyphen = False
            if (
                first_char is not None
                and first_char["text"] == "-"  # type: ignore[index]
                and len(sig_chars) > 1
                and sig_chars[1]["text"].isdigit()  # type: ignore[index]
            ):
                first_char = sig_chars[1]
                strip_leading_hyphen = True
            if (
                add_sentinel
                and first_char is not None
                and first_char["text"].isdigit()  # type: ignore[index]
                and first_char.get("size", 0) >= CHAPTER_NUM_SIZE_THRESHOLD  # type: ignore[index]
            ):
                if strip_leading_hyphen:
                    text = "\x02" + text.lstrip("-").lstrip()
                else:
                    text = "\x02" + text
            result.append(text)
    return "\n".join(result)


def extract_pdf_pages(pdf_path: Path) -> List[str]:
    """
    Extract text from every page of the PDF.

    For the LAI TB layout (two-column, syllable-encoded fonts) we use pdfplumber
    with a custom character-level filter that discards syllable-separator spaces
    and reads each column independently.

    The running header (book name + chapter numbers, top ~50 pt) spans the full
    page width and must NOT be split into columns — the parser relies on it for
    book/chapter detection. Only the body text is split into left/right columns.
    """
    try:
        import pdfplumber  # type: ignore
        pages: List[str] = []
        # Running headers sit in the top ~40-50 pt of the page.
        # On the *first page* of a book there is no running header; instead a
        # large decorative book-title (size ≈ 19 pt) spans both columns at
        # y ≈ 60 pt.  We handle this with two header heights:
        HEADER_HEIGHT = 50.0          # normal pages (running header lives here)
        EXTENDED_HEADER_HEIGHT = 90.0  # first pages of books (decorative title lives here)
        with pdfplumber.open(str(pdf_path)) as pdf:
            total = len(pdf.pages)
            for i, page in enumerate(pdf.pages):
                mid = page.width / 2
                # Header: full width, no sentinel (used only for detection).
                header_crop = page.crop((0, 0, page.width, HEADER_HEIGHT))
                header = _extract_column_text_pdfplumber(header_crop, add_sentinel=False)

                # If the standard header is empty (first page of a book), the
                # decorative title sits just below 50 pt.  Extend the header
                # crop to 90 pt so that "KEJAD" (left column) and "DIAN" (right
                # column) are captured together as "KEJADIAN".  Adjust the body
                # crop start accordingly to avoid double-counting.
                body_start = HEADER_HEIGHT
                if not header.strip():
                    extended_crop = page.crop((0, 0, page.width, EXTENDED_HEADER_HEIGHT))
                    extended = _extract_column_text_pdfplumber(extended_crop, add_sentinel=False)
                    if extended.strip():
                        header = extended
                        body_start = EXTENDED_HEADER_HEIGHT

                # Body: left column then right column
                left = _extract_column_text_pdfplumber(page.crop((0, body_start, mid, page.height)))
                right = _extract_column_text_pdfplumber(page.crop((mid, body_start, page.width, page.height)))
                # Use double newlines between the three sections so that a
                # chapter number at the top of the right column (or at the
                # start of the left column after the header) is preceded by
                # a blank line → prev_blank = True → chapter detection fires.
                t = (header + "\n\n" + left + "\n\n" + right).replace("\x00", "")
                pages.append(t)
                if (i + 1) % 50 == 0:
                    print(f"[extract] {i+1}/{total} pages")
        return pages
    except ImportError:
        print("[extract] pdfplumber not found; falling back to pypdf (syllabification may occur)")

    try:
        from pypdf import PdfReader  # type: ignore
    except Exception as e:  # pragma: no cover
        raise SystemExit(
            "Missing dependency. Install with: pip install pdfplumber pypdf"
        ) from e

    reader = PdfReader(str(pdf_path))
    pages = []
    for i, page in enumerate(reader.pages):
        t = page.extract_text() or ""
        t = t.replace("\x00", "")
        pages.append(t)
        if (i + 1) % 50 == 0:
            print(f"[extract] {i+1}/{len(reader.pages)} pages")
    return pages


# ---- Text cleanup ----

_PAGE_MARKER_RE = re.compile(r"^--\s*\d+\s+of\s+\d+\s*--\s*$", re.IGNORECASE)
_WHITESPACE_RE = re.compile(r"[ \t]+")


def cleanup_page_lines(raw: str) -> List[str]:
    """
    Produces line list with:
      - page markers removed
      - excessive whitespace collapsed
      - hyphenation across line breaks repaired (best-effort)
    """
    lines = [ln.rstrip() for ln in raw.splitlines()]
    # Drop markers like "-- 50 of 1504 --" and empty noise.
    kept: List[str] = []
    for ln in lines:
        s = _WHITESPACE_RE.sub(" ", ln).strip()
        if not s:
            kept.append("")
            continue
        if _PAGE_MARKER_RE.match(s):
            kept.append("")
            continue
        kept.append(s)

    # Repair hyphenation: if a line ends with "-" and next line begins with lowercase,
    # merge them without a space. Otherwise merge with a space later in paragraph build.
    repaired: List[str] = []
    i = 0
    while i < len(kept):
        cur = kept[i]
        if cur.endswith("-") and i + 1 < len(kept):
            nxt = kept[i + 1]
            if nxt and nxt[0].islower():
                repaired.append(cur[:-1] + nxt)
                i += 2
                continue
        repaired.append(cur)
        i += 1
    return repaired


# ---- Page footer/header detection ----

# Right-page running header: "BOOKNAME chapters pagenum"
# e.g.  "KEJADIAN 3, 4  3"  or  "KEJADIAN 7–9  7"
_HEADER_RE_RIGHT = re.compile(
    r"""^(?P<book>[A-Z0-9][A-Z0-9 .'\-]+?)\s+(?P<chapters>[\d]+(?:\s*[,–\-]\s*[\d]+)*)\s+\d+\s*$""",
    re.IGNORECASE,
)
# Left-page running header: "pagenum BOOKNAME chapters"  (no trailing page num)
# e.g.  "4 KEJADIAN 4, 5"
_HEADER_RE_LEFT = re.compile(
    r"""^\d+\s+(?P<book>[A-Z0-9][A-Z0-9 .'\-]+?)\s+(?P<chapters>[\d]+(?:\s*[,–\-]\s*[\d]+)*)\s*$""",
    re.IGNORECASE,
)
# Bracketed right-page: "BOOKNAME chapters [pagenum]"  (Deuterocanonical books)
# e.g.  "KEB. SALOMO 1 [35]"  or  "SIRAKH 15, 16 [73]"
_HEADER_RE_RIGHT_BRACKET = re.compile(
    r"""^(?P<book>[A-Z0-9][A-Z0-9 .'\-]+?)\s+(?P<chapters>[\d]+(?:\s*[,–\-]\s*[\d]+)*)\s+\[\d+\]\s*$""",
    re.IGNORECASE,
)
# Bracketed left-page: "[pagenum] BOOKNAME chapters"
# e.g.  "[36] KEB. SALOMO 1, 2"  or  "[74] SIRAKH 16, 17"
_HEADER_RE_LEFT_BRACKET = re.compile(
    r"""^\[\d+\]\s+(?P<book>[A-Z0-9][A-Z0-9 .'\-]+?)\s+(?P<chapters>[\d]+(?:\s*[,–\-]\s*[\d]+)*)\s*$""",
    re.IGNORECASE,
)
# Keep backward-compat alias used elsewhere.
_FOOTER_RE = _HEADER_RE_RIGHT


def _expand_chapter_tokens(raw: str) -> List[int]:
    """Expand chapter tokens that may include ranges (e.g. '7–9') or comma lists."""
    result: List[int] = []
    # Normalize dashes/en-dashes/em-dashes to plain hyphens
    raw = raw.replace("–", "-").replace("—", "-")
    # Split on commas (keep each chunk intact so ranges survive)
    for chunk in re.split(r",", raw):
        chunk = chunk.strip()
        # A chunk might be "7-9" or "7 -9" or "7- 9" (with spaces around dash)
        m = re.match(r"(\d+)\s*-\s*(\d+)$", chunk)
        if m:
            start, end = int(m.group(1)), int(m.group(2))
            result.extend(range(start, min(end, start + 30) + 1))
        elif chunk.isdigit():
            result.append(int(chunk))
        else:
            # Last resort: extract all digit sequences from the chunk
            nums = re.findall(r"\d+", chunk)
            if len(nums) == 2:
                start, end = int(nums[0]), int(nums[1])
                result.extend(range(start, min(end, start + 30) + 1))
            else:
                result.extend(int(n) for n in nums)
    return result


def detect_page_book_and_chapters(lines: List[str], catalog_by_header: Dict[str, CatalogEntry]) -> Tuple[Optional[CatalogEntry], List[int]]:
    """
    Detects book + chapter numbers from the running header (top 3 lines) or
    the page footer (last 12 lines).

    The pdfplumber extraction places the running header at the top, while the
    original pypdf path used footer lines.  Both are checked so either layout
    works.  Chapter tokens may be comma-separated or range format ("7–9").
    """
    def norm(s: str) -> str:
        s = s.upper()
        s = "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))
        s = s.replace("—", "-")
        s = re.sub(r"\s+", " ", s).strip()
        return s

    prefix_patterns = [
        r"^KITAB\s+",
        r"^INJIL\s+",
        r"^SURAT\s+PAULUS(\s+YANG\s+(PERTAMA|KEDUA))?\s+KEPADA\s+",
        r"^SURAT\s+PAULUS\s+KEPADA\s+",
        r"^SURAT\s+KEPADA\s+",
        r"^SURAT\s+",
        r"^WAHYU\s+KEPADA\s+",
    ]

    # Check header area (top 3) then footer area (last 12), header first.
    head = [ln for ln in lines[:3] if ln.strip()]
    tail = [ln for ln in lines[-12:] if ln.strip()]
    for ln in head + list(reversed(tail)):
        s = ln.strip()
        # Try all header format variants in order of specificity.
        m = _HEADER_RE_RIGHT.match(s)
        if not m:
            m = _HEADER_RE_LEFT.match(s)
        if not m:
            m = _HEADER_RE_RIGHT_BRACKET.match(s)
        if not m:
            m = _HEADER_RE_LEFT_BRACKET.match(s)
        if not m:
            # Also try after stripping a leading number (covers footer variants).
            s2 = re.sub(r"^\d{1,4}\s+", "", s)
            m = _HEADER_RE_RIGHT.match(s2)
        if not m:
            # Handle attached-digit headers like "972MALEAKHI 1" or "974MALEAKHI 3, 4"
            # where the page number is directly concatenated with the book name.
            s3 = re.sub(r"^\d+(?=[A-Z])", "", s)
            if s3 != s:
                m = _HEADER_RE_RIGHT.match(s3) or _HEADER_RE_LEFT.match(s3)
        if not m:
            continue
        book_raw = m.group("book").strip()
        chapters_raw = m.group("chapters")

        nb = norm(book_raw)
        stripped = nb
        for pat in prefix_patterns:
            stripped = re.sub(pat, "", stripped).strip()

        candidates = [
            nb,
            nb.replace("-", " "),
            re.sub(r"\s+", "", nb),
            stripped,
            stripped.replace("-", " "),
            re.sub(r"\s+", "", stripped),
        ]
        entry: Optional[CatalogEntry] = None
        for c in candidates:
            if c in catalog_by_header:
                entry = catalog_by_header[c]
                break

        chapters = _expand_chapter_tokens(chapters_raw)
        if entry or chapters:
            return entry, chapters

    return None, []

def detect_book_from_page_head(lines: List[str], catalog_by_header: Dict[str, CatalogEntry]) -> Optional[CatalogEntry]:
    """
    Fallback: detect a new book from a header-like line near the top of a page.
    Many PDFs print the book title in the running header (sometimes without chapter list).
    """
    def scrub(raw: str) -> str:
        raw = raw.strip()
        raw = re.sub(r"^\[\d+\]\s*", "", raw)       # leading [123] bracket
        raw = re.sub(r"^\d{1,4}\s+", "", raw)       # leading page/chapter number with space
        raw = re.sub(r"^\d+(?=[A-Z])", "", raw)     # attached leading digits "972MALEAKHI" → "MALEAKHI"
        raw = re.sub(r"\[\d+\]", "", raw).strip()   # inline [123] bracket
        return raw

    head = [scrub(ln) for ln in lines[:60] if ln.strip()]

    def norm(s: str) -> str:
        s = s.upper()
        s = "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))
        s = s.replace("—", "-")
        s = re.sub(r"\s+", " ", s).strip()
        return s

    def header_variants(raw: str) -> List[str]:
        raw = raw.strip()
        variants = [raw]
        # Strip trailing page/chapter numbers, e.g. "1 YOHANES 3" / "OBADJA 1"
        variants.append(re.sub(r"\s+\d{1,4}\s*$", "", raw).strip())
        # Strip "BOOK 1 , 2" patterns
        variants.append(re.sub(r"\s+\d+(?:\s*,\s*\d+)+\s*$", "", raw).strip())
        # Strip "BOOK 1:2" patterns (rare in headers)
        variants.append(re.sub(r"\s+\d+:\d+\s*$", "", raw).strip())
        # Strip running-header trailing pattern: "BOOKNAME N, M  P" or "BOOKNAME N–M"
        # e.g. "KEJADIAN 3, 4  3" → "KEJADIAN", "KEJADIAN 1–3" → "KEJADIAN"
        variants.append(re.sub(r"\s+[\d,\s\-–]+$", "", raw).strip())
        # De-duplicate while preserving order
        out = []
        seen = set()
        for v in variants:
            if v and v not in seen:
                seen.add(v)
                out.append(v)
        return out

    def candidate_keys(raw: str) -> List[str]:
        nb = norm(raw)
        prefix_patterns = [
            r"^KITAB\s+",
            r"^INJIL\s+",
            r"^SURAT\s+PAULUS(\s+YANG\s+(PERTAMA|KEDUA))?\s+KEPADA\s+",
            r"^SURAT\s+PAULUS\s+KEPADA\s+",
            r"^SURAT\s+KEPADA\s+",
            r"^SURAT\s+",
            r"^WAHYU\s+KEPADA\s+",
        ]
        stripped = nb
        for pat in prefix_patterns:
            stripped = re.sub(pat, "", stripped).strip()
        return [
            nb,
            nb.replace("-", " "),
            re.sub(r"\s+", "", nb),
            stripped,
            stripped.replace("-", " "),
            re.sub(r"\s+", "", stripped),
        ]

    # Collect title-candidate lines (short, letter-rich, near the top).
    title_lines: List[str] = []
    for ln in head:
        if len(ln) > 60:
            continue
        letters = sum(1 for ch in ln if ch.isalpha())
        if letters < 4:
            continue
        title_lines.append(ln)

    # --- Pass 1: try multi-line joins (most-specific first) ---
    # This catches multi-line book titles like:
    #   "SURAT"  →  "YOHANES"  →  "YANG PERTAMA"  →  "SURAT YOHANES YANG PERTAMA"
    # A single-line match for "YOHANES" alone would give the wrong book.
    max_join = min(6, len(title_lines))
    for n in range(max_join, 1, -1):  # n=max down to 2
        for start in range(len(title_lines) - n + 1):
            joined = " ".join(title_lines[start : start + n])
            if len(joined) > 80:
                continue
            for hv in header_variants(joined):
                for key in candidate_keys(hv):
                    e = catalog_by_header.get(key)
                    if e:
                        return e

    # --- Pass 2: single-line match (fallback) ---
    for ln in title_lines:
        for hv in header_variants(ln):
            for key in candidate_keys(hv):
                e = catalog_by_header.get(key)
                if e:
                    return e

    return None


def match_book_title_line(line: str, catalog_by_header: Dict[str, CatalogEntry]) -> Optional[CatalogEntry]:
    """
    Detect a book title from a single line anywhere in the page (useful when
    one book ends and another begins mid-page for short books/letters).

    IMPORTANT: leading digits are stripped *after* trying the full form so that
    numbered-book headers like "1 YOHANES 2, 3 269" resolve to 1yoh (not yoh).
    The fallback path handles left-page running headers like "270 1 YOHANES 3, 4"
    where the leading page number must be stripped first.
    """
    ln = line.strip()
    ln = re.sub(r"^\[\d+\]\s*", "", ln)       # leading [123] annotation
    ln = re.sub(r"\[\d+\]", "", ln).strip()   # inline [123] annotation
    if not ln:
        return None
    if len(ln) > 70:
        return None

    def norm(s: str) -> str:
        s = s.upper()
        s = "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))
        s = s.replace("—", "-")
        s = re.sub(r"\s+", " ", s).strip()
        return s

    def header_variants(raw: str) -> List[str]:
        raw = raw.strip()
        variants = [raw]
        variants.append(re.sub(r"\s+\d{1,4}\s*$", "", raw).strip())
        variants.append(re.sub(r"\s+\d+(?:\s*,\s*\d+)+\s*$", "", raw).strip())
        variants.append(re.sub(r"\s+\d+:\d+\s*$", "", raw).strip())
        # Running-header trailing pattern: "BOOKNAME N, M  P" or "BOOKNAME N–M"
        variants.append(re.sub(r"\s+[\d,\s\-–]+$", "", raw).strip())
        out = []
        seen = set()
        for v in variants:
            if v and v not in seen:
                seen.add(v)
                out.append(v)
        return out

    def candidate_keys(raw: str) -> List[str]:
        nb = norm(raw)
        prefix_patterns = [
            r"^KITAB\s+",
            r"^INJIL\s+",
            r"^SURAT\s+PAULUS(\s+YANG\s+(PERTAMA|KEDUA))?\s+KEPADA\s+",
            r"^SURAT\s+PAULUS\s+KEPADA\s+",
            r"^SURAT\s+KEPADA\s+",
            r"^SURAT\s+",
            r"^WAHYU\s+KEPADA\s+",
        ]
        stripped = nb
        for pat in prefix_patterns:
            stripped = re.sub(pat, "", stripped).strip()
        return [
            nb,
            nb.replace("-", " "),
            re.sub(r"\s+", "", nb),
            stripped,
            stripped.replace("-", " "),
            re.sub(r"\s+", "", stripped),
        ]

    # Pass 1: try the full line WITHOUT stripping the leading digit/number.
    # This correctly resolves "1 YOHANES 2, 3 269" → "1 YOHANES" → 1yoh
    # instead of "YOHANES" → yoh after stripping the "1 " prefix.
    for hv in header_variants(ln):
        for key in candidate_keys(hv):
            e = catalog_by_header.get(key)
            if e:
                return e

    # Pass 2: strip leading page/chapter number and retry.
    # Handles left-page running headers like "270 1 YOHANES 3, 4" where
    # "270" is the page number (not part of the book name).
    ln2 = re.sub(r"^\d{1,4}\s+", "", ln)
    if ln2 != ln:
        for hv in header_variants(ln2):
            for key in candidate_keys(hv):
                e = catalog_by_header.get(key)
                if e:
                    return e

    return None


# ---- Chapter & verse parsing ----

_CHAPTER_START_RE = re.compile(r"^(?P<num>\d{1,3})\s+(?P<rest>.+)$")

# Verse markers commonly appear after punctuation or line breaks.
_INLINE_VERSE_SPLIT_RE = re.compile(r"""(?:^|[\n\r]|[.!?;"”])\s*(\d{1,3})\s+""")


def _normalize_text(s: str) -> str:
    s = s.replace("\u00ad", "")  # soft hyphen
    s = re.sub(r"\s+\n", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    s = re.sub(r"[ \t]{2,}", " ", s)
    return s.strip()


def split_chapter_into_verses(chapter_text: str) -> List[Dict[str, object]]:
    """
    Input: full chapter text where verse 1 is implicit.
    Tokens prefixed with '###' are section headings tagged by the caller.
    Output: [{"v": 1, "t": "...", "h": "Optional heading"}, ...]
    """
    # --- Step 1: extract embedded ###Heading tokens before text normalization ---
    # Map each heading to the text token that immediately follows it; we'll later
    # attach it to whichever verse that token belongs to.
    # We insert a unique marker \x01heading\x02 directly before the next non-heading
    # word so it survives the join and can be matched per-verse after splitting.
    tokens = chapter_text.split(" ")
    pending_heading: Optional[str] = None
    assembled: List[str] = []
    for tok in tokens:
        if tok.startswith("###"):
            # Each heading is a single space-delimited token; internal spaces were
            # encoded as \x1F by the caller so the heading doesn't get fragmented.
            frag = tok[3:].replace("\x1f", " ").strip()
            if frag:
                if pending_heading:
                    pending_heading += " " + frag
                else:
                    pending_heading = frag
        else:
            if pending_heading and tok.strip():
                assembled.append(f"\x01{pending_heading}\x02{tok}")
                pending_heading = None
            else:
                assembled.append(tok)
    clean_text = " ".join(assembled)

    t = _normalize_text(clean_text)
    if not t:
        return []

    # --- Step 2: standard verse splitting ---
    matches = list(_INLINE_VERSE_SPLIT_RE.finditer(t))
    if not matches:
        verse = {"v": 1, "t": t}
        _extract_heading(verse)
        return [verse]

    verses: List[Dict[str, object]] = []
    first = matches[0].start()
    v1_text = t[:first].strip()
    if v1_text:
        verses.append({"v": 1, "t": v1_text})

    for idx, m in enumerate(matches):
        vnum = int(m.group(1))
        start = m.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(t)
        body = t[start:end].strip()
        if not body:
            continue
        verses.append({"v": vnum, "t": body})

    # Ensure sorted and unique by verse number, keeping first occurrence.
    out: List[Dict[str, object]] = []
    seen: set[int] = set()
    for v in sorted(verses, key=lambda x: int(x["v"])):  # type: ignore[index]
        vn = int(v["v"])  # type: ignore[index]
        if vn in seen:
            continue
        seen.add(vn)
        _extract_heading(v)
        out.append(v)
    return out


def _extract_heading(verse: Dict[str, object]) -> None:
    """
    If verse text starts with \\x01heading\\x02body, split off the heading.
    Any \\x01...\\x02 patterns that appear *mid-verse* (not at position 0) are
    false-positive section-heading tags (regular uppercase verse-continuation
    lines).  Strip them to keep verse text clean.
    """
    text = str(verse.get("t", ""))
    # Extract heading only if it sits at the very start of the verse text.
    m = re.match(r"^\x01(.*?)\x02(.*)", text, re.DOTALL)
    if m:
        verse["h"] = m.group(1).strip()
        text = m.group(2).strip()
    # Strip any remaining mid-verse markers (false positives) and orphaned halves.
    text = re.sub(r"\x01[^\x02]*\x02", "", text)   # complete mid-verse markers
    text = text.replace("\x01", "").replace("\x02", "")  # orphaned halves
    verse["t"] = text


def parse_pdf_to_books(
    pages: List[str],
    catalog_by_header: Dict[str, CatalogEntry],
    *,
    stop_at_kamus: bool = True,
) -> Dict[str, Dict[str, List[Dict[str, object]]]]:
    """
    Returns: slug -> chapterStr -> verses[]
    """
    books: Dict[str, Dict[str, List[Dict[str, object]]]] = {}

    current_entry: Optional[CatalogEntry] = None
    current_chapter: Optional[int] = None
    current_buffer: List[str] = []

    def flush_chapter():
        nonlocal current_buffer, current_chapter, current_entry
        if not current_entry or not current_chapter:
            current_buffer = []
            return
        chapter_text = " ".join([x for x in current_buffer if x.strip()])
        verses = split_chapter_into_verses(chapter_text)
        if not verses:
            current_buffer = []
            return
        slug = current_entry.slug
        books.setdefault(slug, {})
        ch_key = str(current_chapter)
        # Safety net: never overwrite a longer (more complete) chapter with a shorter one.
        # This guards against false chapter restarts (e.g. from running header sentinels)
        # clobbering correctly parsed content.
        existing = books[slug].get(ch_key)
        if existing and len(existing) > len(verses):
            current_buffer = []
            return
        books[slug][ch_key] = verses
        current_buffer = []

    for page_idx, raw in enumerate(pages, start=1):
        lines = cleanup_page_lines(raw)
        total_lines = len(lines)

        # Optional: stop when reaching glossary section.
        if stop_at_kamus and any(ln.strip().upper() == "KAMUS" for ln in lines[:40]):
            print(f"[parse] Detected 'KAMUS' at page {page_idx}; stopping parse.")
            break

        # Try footer-based detection first; then fall back to running header/title detection.
        detected_entry, page_chapters = detect_page_book_and_chapters(lines, catalog_by_header)
        if detected_entry is None:
            detected_entry = detect_book_from_page_head(lines, catalog_by_header)

        # Track the book that was active BEFORE any page-level change so that
        # a sentinel belonging to the last chapter of the old book (e.g. 1 Sam 31
        # on the first page of 2 Samuel) can still be attributed correctly.
        previous_entry: Optional[CatalogEntry] = current_entry

        if detected_entry is not None:
            if current_entry is None:
                current_entry = detected_entry
            elif detected_entry.slug != current_entry.slug:
                # Book changed: flush open chapter.
                flush_chapter()
                current_entry = detected_entry
                current_chapter = None

        # Keep only plausible chapter numbers for the current book.
        chapter_candidates = set()
        if current_entry:
            for c in page_chapters:
                if 1 <= c <= current_entry.chapter_count:
                    chapter_candidates.add(c)

        # Remember which book was determined at the page level (before line scanning).
        # A partial title-stack match (e.g. "SURAT YOHANES" before "YANG PERTAMA" is
        # seen) must not downgrade the page-level detection to a less-specific book.
        page_level_entry = current_entry

        # Walk lines; detect chapter starts; accumulate text.
        prev_blank = True
        title_stack: List[str] = []
        page_content_lines: List[str] = []
        for line_idx, ln in enumerate(lines):
            s = ln.strip()
            if not s:
                prev_blank = True
                title_stack = []
                continue

            # Peel off the large-chapter-number sentinel (\x02) at the start of
            # the stripped line.  The sentinel is checked later in the chapter-start
            # detection block; all other checks work on the plain text.
            _sentinel = s.startswith("\x02")
            if _sentinel:
                s = s[1:]
                # Some PDFs omit the space between the chapter number and the
                # following text (e.g. "3Lihat, Aku..." or "7Sesudah itu…").
                # Insert a space so _CHAPTER_START_RE can match.
                s = re.sub(r"^(\d+)([A-Za-z])", r"\1 \2", s)

            # Skip common PDF production artifacts.
            if "indb" in s.lower() or re.search(r"\bnew size\b", s.lower()):
                prev_blank = False
                title_stack = []
                continue

            # Book boundary detection mid-page (important for short books/letters).
            # Also handle multi-line titles like:
            #   SURAT
            #   YOHANES
            #   YANG PERTAMA
            def is_titleish(x: str) -> bool:
                if len(x) > 70:
                    return False
                # Must start with uppercase (verse-continuation lines usually
                # start lowercase, e.g. "dan Tuhan berfirman…")
                if x and x[0].islower():
                    return False
                # No sentence-ending / list punctuation
                if re.search(r"[.:;,]", x):
                    return False
                # Must not start with a digit (that would be a verse/chapter number)
                if x and x[0].isdigit():
                    return False
                letters = sum(1 for ch in x if ch.isalpha())
                return letters >= 4

            if is_titleish(s):
                title_stack.append(s)
                title_stack = title_stack[-6:]
            else:
                title_stack = []

            # Try title_stack joins FIRST (more specific / longer matches win).
            # e.g. "SURAT YOHANES YANG PERTAMA" → 1yoh, before "YOHANES" alone → yoh.
            mid_entry = None
            if title_stack:
                for n in range(min(6, len(title_stack)), 1, -1):
                    joined = " ".join(title_stack[-n:])
                    mid_entry = match_book_title_line(joined, catalog_by_header)
                    if mid_entry is not None:
                        break
            # Fall back to single-line match only if no multi-line join succeeded.
            # Guard: only attempt the single-line fallback when the line looks like a
            # title (is_titleish) OR starts with a digit+uppercase-word (e.g. "1 SAMUEL").
            # Body-text lines like "kebijaksanaan" (lowercase Indonesian word) would
            # otherwise match short single-word book names like keb="Kebijaksanaan".
            _line_looks_like_title = is_titleish(s) or bool(re.match(r"^\d\s+[A-Z]", s))
            if mid_entry is None and _line_looks_like_title:
                mid_entry = match_book_title_line(s, catalog_by_header)
            if mid_entry is not None:
                # If the PDF prints the book title *after* the content on the same page
                # (observed for some very short letters), retroactively assign the page's
                # collected content to this book's chapter 1.
                if (
                    (current_chapter is None)
                    and (not current_buffer)
                    and page_content_lines
                    and (line_idx > int(total_lines * 0.6))
                ):
                    current_entry = mid_entry
                    current_chapter = 1
                    current_buffer = page_content_lines.copy()
                    prev_blank = True
                    title_stack = []
                    continue

                # Variant: we already started buffering (likely under the previous book),
                # but a late title indicates this page's content belongs to a new book.
                if (
                    current_entry is not None
                    and (mid_entry.slug != current_entry.slug)
                    and current_buffer
                    and (line_idx > int(total_lines * 0.6))
                ):
                    current_entry = mid_entry
                    if current_chapter is None:
                        current_chapter = 1
                    prev_blank = True
                    title_stack = []
                    continue

                if current_entry is None:
                    current_entry = mid_entry
                    current_chapter = None
                    current_buffer = []
                elif mid_entry.slug != current_entry.slug:
                    # Guard: don't override a page-level detection with a partial
                    # mid-title match.  Example: page_level_entry=1yoh (detected
                    # from the full "SURAT YOHANES YANG PERTAMA" title), but the
                    # line loop sees "SURAT YOHANES" (only 2 of 3 title lines) and
                    # matches the less-specific yoh (Gospel of John).  When the
                    # title_stack has ≥ 2 lines we are still accumulating a
                    # multi-line title — don't change books yet; wait for the next
                    # line to complete the full join (e.g. "YANG PERTAMA" → 1yoh).
                    if (
                        page_level_entry is not None
                        and current_entry.slug == page_level_entry.slug
                        and mid_entry.slug != page_level_entry.slug
                        and len(title_stack) >= 2
                    ):
                        # Preserve title_stack so the next titleish line can
                        # complete the multi-line join ("YANG PERTAMA" → 1yoh).
                        prev_blank = True
                        continue
                    flush_chapter()
                    current_entry = mid_entry
                    current_chapter = None
                    current_buffer = []
                prev_blank = True
                title_stack = []
                continue

            # Skip recurring cross-ref line patterns like "33:54: Bil. 26:54-56 ..."
            if re.match(r"^\d+:\d+:", s):
                prev_blank = False
                continue

            # Skip pure page numbers or isolated numeric noise
            if re.match(r"^\d{1,4}$", s):
                if current_entry:
                    num_only = int(s)
                    if 1 <= num_only <= current_entry.chapter_count and (prev_blank or line_idx < 60):
                        # Some books print chapter numbers on their own line (notably in Deuterocanonika/letters).
                        flush_chapter()
                        current_chapter = num_only
                        current_buffer = []
                        prev_blank = False
                        continue
                prev_blank = False
                continue

            # Strip a single leading hyphen (hanging-hyphen column artefact) when
            # what follows looks like a chapter or verse number.  This handles
            # chapters that start in the right column with "-15 Dan aku melihat…".
            # Only strip for the purpose of chapter detection; verse text already
            # accumulated in current_buffer is unaffected.
            s_for_chapter = s
            if s_for_chapter.startswith("-") and len(s_for_chapter) > 1 and s_for_chapter[1].isdigit():
                s_for_chapter = s_for_chapter[1:].lstrip()

            # Chapter start line (best-effort):
            # - at paragraph boundary (prev_blank)
            # - number is listed in page footer candidates OR we have no candidates but we're early
            # - OR the extractor confirmed a large-font chapter number (sentinel _sentinel)
            m = _CHAPTER_START_RE.match(s_for_chapter)
            if m and current_entry:
                num = int(m.group("num"))
                rest = m.group("rest").strip()

                is_chapter_start = False
                if _sentinel and 1 <= num <= current_entry.chapter_count:
                    # Font size confirms this is a chapter heading, not an inline verse num.
                    # Guard: if rest is only a short book abbreviation (≤ 4 letters, no spaces
                    # with long words), this is a decorative "1 SAM" header, not chapter content.
                    long_word = any(len(w) >= 5 for w in rest.split())
                    if rest and not long_word and len(rest) <= 8:
                        # Looks like "SAM", "RAJA", "TAWA" etc. — skip, don't start a chapter
                        pass
                    else:
                        is_chapter_start = True
                elif (
                    _sentinel
                    and num > current_entry.chapter_count
                    and previous_entry is not None
                    and previous_entry.slug != current_entry.slug
                    and 1 <= num <= previous_entry.chapter_count
                    and line_idx < 30
                ):
                    # The sentinel belongs to the PREVIOUS book's last chapter that
                    # spills onto this page (e.g. 1 Samuel 31 on the first page of
                    # 2 Samuel).  Restore the previous entry, flush the old buffer,
                    # then start the correct chapter.
                    long_word = any(len(w) >= 5 for w in rest.split())
                    if not (rest and not long_word and len(rest) <= 8):
                        flush_chapter()
                        current_entry = previous_entry
                        current_chapter = num
                        current_buffer = [rest] if rest else []
                        prev_blank = False
                        continue
                elif prev_blank and num in chapter_candidates and current_chapter != num:
                    # Only start a new chapter if we are not already in it.
                    # Guards against verse N of chapter N (e.g. Sirach 15:15 = "15 Asal
                    # sungguh…") being mistaken for a chapter-N restart when chapter N
                    # is already active and the verse number happens to be in chapter_candidates.
                    is_chapter_start = True
                elif num in chapter_candidates and current_chapter != num and line_idx < 25:
                    # Chapter headings are typically near the top of a page; allow without blank line.
                    is_chapter_start = True
                elif prev_blank and current_chapter is None and 1 <= num <= current_entry.chapter_count and num <= 150:
                    # First chapter on first pages for a book sometimes lacks footer hints.
                    is_chapter_start = True
                elif current_chapter is None and 1 <= num <= current_entry.chapter_count and line_idx < 25:
                    # Fallback for book starts where we detected the book header but not footer chapter list.
                    is_chapter_start = True

                if is_chapter_start:
                    # If the last item in the current buffer is a section heading
                    # (###…) it was placed there by a heading that immediately
                    # precedes this chapter sentinel.  Move it to the NEW chapter so
                    # it gets attached to the chapter's first verse rather than the
                    # last verse of the old chapter.
                    trailing_heading: Optional[str] = None
                    if current_buffer and current_buffer[-1].startswith("###"):
                        trailing_heading = current_buffer.pop()
                    flush_chapter()
                    current_chapter = num
                    if trailing_heading:
                        current_buffer = ([trailing_heading] + ([rest] if rest else []))
                    else:
                        current_buffer = [rest] if rest else []
                    # Set prev_blank=True so that a section heading appearing on the
                    # very next line after a chapter sentinel is correctly detected.
                    # (e.g. "Allah menciptakan langit dan bumi serta isinya" follows
                    # the Genesis ch1 sentinel immediately.)
                    prev_blank = True
                    continue

            # If we have an open chapter, accumulate. Otherwise ignore until we find one.
            if current_entry and current_chapter is None:
                # Many short books/letters don't print a chapter heading line.
                # Start chapter 1 on first real content line.
                if not is_titleish(s) and not re.match(r"^\d+:\d+:", s):
                    current_chapter = 1
                    current_buffer = [s]
                    prev_blank = False
                    continue

            # A section heading must be:
            #   1. Multi-word (≥ 2 words) — single capitalised words are proper nouns
            #   2. Preceded by a blank line (prev_blank) — headings follow structural
            #      breaks, not mid-sentence line-wraps or genealogy lines like
            #      "Elkana bin Yeroham bin Elihu bin Tohu bin"
            is_section_heading = is_titleish(s) and len(s.split()) >= 2 and prev_blank

            if current_entry and current_chapter:
                # Tag section headings with a sentinel so split_chapter_into_verses
                # can extract them separately instead of merging into verse text.
                # Internal spaces are replaced with \x1F (unit-separator) so the
                # whole heading survives as a single space-delimited token when the
                # buffer is later joined with spaces.
                if is_section_heading:
                    current_buffer.append("###" + s.replace(" ", "\x1f"))
                else:
                    current_buffer.append(s)

            # Collect page content lines for potential retro-assignment when titles appear late.
            if not is_titleish(s) and not re.match(r"^\d+:\d+:", s):
                page_content_lines.append(s)

            # Section headings signal a structural boundary, so treat them like
            # a blank line — the line immediately following (typically a chapter
            # number) should see prev_blank=True.
            if is_section_heading and current_entry and current_chapter:
                prev_blank = True
            else:
                prev_blank = False

        # --- Special-case fallback for very short letters whose title appears after content ---
        # Some pages place the book title at the bottom (after the entire letter text),
        # making streaming detection unreliable. If we see a clear title block, carve the
        # whole page's content (before that block) into chapter 1.
        def page_has_title(block: List[str], phrase: str) -> bool:
            joined = " ".join(
                "".join(ch for ch in unicodedata.normalize("NFKD", x.upper()) if not unicodedata.combining(ch))
                for x in block
                if x.strip()
            )
            joined = re.sub(r"\s+", " ", joined).strip()
            return phrase in joined

        upper_lines = [ln.strip() for ln in lines if ln.strip()]
        for phrase, slug in [
            ("SURAT YOHANES YANG KEDUA", "2yoh"),
            ("SURAT YOHANES YANG KETIGA", "3yoh"),
        ]:
            if slug in books:
                continue
            if not page_has_title(upper_lines[-40:], phrase):
                continue

            # Find first "SURAT" line near the bottom and take content before it.
            cut_idx = None
            for i, ln in enumerate(lines):
                if ln.strip().upper() == "SURAT":
                    cut_idx = i
                    break
            if cut_idx is None:
                continue

            content = []
            for ln in lines[:cut_idx]:
                s = ln.strip()
                if not s:
                    continue
                if "indb" in s.lower() or re.search(r"\bnew size\b", s.lower()):
                    continue
                if re.match(r"^\d+:\d+:", s):
                    continue
                # Keep standalone '1' (chapter marker) and verse-numbered lines.
                content.append(s)

            chapter_text = " ".join(content)
            verses = split_chapter_into_verses(chapter_text)
            if verses:
                books.setdefault(slug, {})
                books[slug]["1"] = verses

        if page_idx % 100 == 0:
            print(f"[parse] processed {page_idx}/{len(pages)} pages; books={len(books)}")

    flush_chapter()
    return books


def write_per_book_json(out_dir: Path, books: Dict[str, Dict[str, List[Dict[str, object]]]]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for slug, bookdata in books.items():
        # Keep chapters in numeric order.
        ordered = {k: bookdata[k] for k in sorted(bookdata.keys(), key=lambda x: int(x))}
        (out_dir / f"{slug}.json").write_text(
            json.dumps(ordered, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


def write_seed_json(seed_path: Path, books: Dict[str, Dict[str, List[Dict[str, object]]]], version: str) -> None:
    payload = {
        "version": version,
        "generatedAt": _now_iso(),
        "note": "Generated offline from PDF. Ensure licensing before distribution.",
        "books": books,
    }
    seed_path.parent.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf", required=True, type=Path, help="Path to kitab_umat_katolik.pdf")
    ap.add_argument(
        "--catalog-swift",
        required=True,
        type=Path,
        help="Path to BibleCatalog.swift (used to build book mapping)",
    )
    ap.add_argument(
        "--out-dir",
        required=True,
        type=Path,
        help="Directory for per-book JSON outputs (e.g. generated/tb)",
    )
    ap.add_argument(
        "--seed-json",
        type=Path,
        default=None,
        help="Optional output path for a single bible_seed JSON file",
    )
    ap.add_argument("--version", default="tb", help="Version identifier (default: tb)")
    ap.add_argument(
        "--no-stop-at-kamus",
        action="store_true",
        help="Parse beyond the 'KAMUS' section (not recommended)",
    )
    args = ap.parse_args()

    if not args.pdf.exists():
        raise SystemExit(f"PDF not found: {args.pdf}")
    if not args.catalog_swift.exists():
        raise SystemExit(f"BibleCatalog.swift not found: {args.catalog_swift}")

    catalog = load_catalog_from_swift(args.catalog_swift)
    print(f"[catalog] loaded {len({e.slug for e in catalog.values()})} books (with aliases)")

    pages = extract_pdf_pages(args.pdf)
    print(f"[extract] done: {len(pages)} pages")

    books = parse_pdf_to_books(
        pages,
        catalog,
        stop_at_kamus=not args.no_stop_at_kamus,
    )
    print(f"[parse] done: books={len(books)}")

    write_per_book_json(args.out_dir, books)
    print(f"[write] per-book JSON → {args.out_dir}")

    if args.seed_json:
        write_seed_json(args.seed_json, books, args.version)
        print(f"[write] seed JSON → {args.seed_json}")


if __name__ == "__main__":
    main()

