#!/usr/bin/env python3
"""
clean_refrains.py
=================
Applies surgical post-processing to lagumisa_refrains.json.
Only removes known artifact patterns — no word-length filters.

Artifacts handled:
  1. "Gaya X"  regional style labels at text start
  2. Watermarks: sa.web.id, web.id, "w e b", etc.
  3. SATB notation duplication in Pentecost images
  4. Leading/inline OCR noise tokens (garbled sheet-music beams)
  5. Stray symbols: ®, •, *, |-, |, " II "
  6. Musical annotation noise: "sol = ...", "Gregorian ...", "Dinyanyikan tiga kali..."
  7. Cyrillic OCR mis-reads: к→k, А→A, В→B, а→a
  8. "Tus\"-" OCR glitch for "Tuhan"
  9. "X -Y" (space-before-hyphen) syllable joins → "XY"
 10. "= " noise inside words (e.g., "ka = mi" → "kami")
 11. Entries that are entirely notation noise → removed from output
"""

import json
import re
from pathlib import Path

REFRAINS_PATH = Path(__file__).parent.parent / "BibleApp" / "lagumisa_refrains.json"

# ---------------------------------------------------------------------------
# Known "Gaya X" place-name prefixes — exhaustive list from this scrape
# ---------------------------------------------------------------------------
GAYA_PLACES = (
    r'Timor(?:\s*\(\s*Dawan\s*\))?'
    r'|Banjar'
    r'|Nias'
    r'|DawanTimor'
    r'|Dawan\s+Timor'
    r'|Wani(?:\s*\([^)]*\))?'
    r'|Dayak(?:\s+\w+)?'          # "Dayak" or "Dayak Xxx"
    r'|Maluku'
    r'|Daya\s+Ribun'
    r'|Sumatera\s+Selatan'
    r'|Lampung'
    r'|Toraja'
    r'|Batak'
    r'|Jawa'
    r'|Sunda'
    r'|Flores'
    r'|Papua'
    r'|NTT'
)
GAYA_RE = re.compile(
    r'^[Gg]aya\s+(?:' + GAYA_PLACES + r')\s+',
    re.UNICODE,
)

# ---------------------------------------------------------------------------
# OCR noise token patterns — garbled sheet-music staff/beam artefacts
# These tokens are detected by:
#   (a) containing 2+ consecutive digits, OR
#   (b) containing 3+ consecutive identical letters (e.g. "lll", "iii"), OR
#   (c) the specific "Gridlioiliolil"-class repeated syllable pattern
# ---------------------------------------------------------------------------
NOISE_TOKEN_RE = re.compile(
    r'\b\S*\d{2,}\S*\b'                    # token with 2+ consecutive digits
    r'|\b\S*([a-zA-Z])\1\1\S*\b'           # token with 3+ same letter in a row
    r'|\b[A-Z][a-z]{2,}(?:iol|ioi|lio|lil|loi){2,}[a-z]*\b'  # "Gridlioiliolil"
    r'|\bi\.Lill\b'                         # specific artefact "i.Lill"
    r'|\S*¿\S*',                            # token containing ¿ (OCR noise from curved notation)
    re.UNICODE,
)

# ---------------------------------------------------------------------------
# Entry-level "entirely noise" check — entry is not a real refrain
# ---------------------------------------------------------------------------
ENTIRELY_NOISE_PREFIXES = (
    'sol = ',   # a-malam-paskah-8: Gregorian chant notation
)


def clean(text: str) -> str:
    # 1. Gaya X prefix
    text = GAYA_RE.sub('', text)

    # 2. Watermark strings (case-insensitive — "Sa.web", "sa.web.id", etc.)
    # Note: ordered longest-first so subpatterns don't short-circuit
    text = re.sub(
        r'\s*(?:sa\.web\.id|web\.id|sa\.web\.?|\.?\s*i\s*d\.\s*a\.web\.?)\s*',
        ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\bw\s+e\s+b\b\s*', '', text, flags=re.IGNORECASE)   # "w e b" spaced watermark

    # 3. SATB duplication (Pentecost images have two versions stacked)
    #    Keep only text before "SATB Do=" or "SATB|"
    text = re.sub(r'\s*SATB\s.*$', '', text, flags=re.DOTALL)

    # 4. Leading period/dot artefact "." at very start
    text = re.sub(r'^[\.\s]+', '', text)

    # 5. Stray symbols
    text = text.replace('®', '').replace('•', '').replace('*', '')
    text = re.sub(r'\|[-\s]*', '', text)    # "|-" or "|"
    text = re.sub(r'\s*"\s*', '', text)     # stray quote marks from OCR
    text = re.sub(r'\s*\(\s*bumi\s*\)\s*', ' ', text)   # "(bumi)" annotation
    text = re.sub(r'\bIni1\b', '', text)    # "Ini1" → artefact (p-pesta-stmarkus)

    # 6. Musical annotation noise
    text = re.sub(r'\bsol\s*=\s*[^;]+;\s*', '', text)
    text = re.sub(r'\b[Gg]regorian\b\s*', '', text)
    text = re.sub(r'Dinyanyikan\s+tiga\s+kali.*$', '', text, flags=re.DOTALL)

    # 7. Cyrillic OCR mis-reads (common for к → k, А → A, В → B, etc.)
    for cyrillic, latin in [('к', 'k'), ('А', 'A'), ('В', 'B'), ('а', 'a'), ('е', 'e')]:
        text = text.replace(cyrillic, latin)

    # 8. "Tus\"- han" OCR glitch → "Tuhan"
    text = re.sub(r'Tus["\'\-]+\s*han', 'Tuhan', text)

    # 9. "X -Y" (space before hyphen, no space after) → "XY"
    text = re.sub(r"([A-Za-z'])\s+-([A-Za-z'])", r'\1\2', text)

    # 10. "ka = mi" style → "kami"  (isolated "=" surrounded by word chars)
    text = re.sub(r'([A-Za-z])\s+=\s+([A-Za-z])', r'\1\2', text)
    text = re.sub(r'([A-Za-z])\s*_\s*([A-Za-z])', r'\1\2', text)  # "aba _ di" → "abadi"

    # 11. OCR noise tokens (garbled beam/staff artefacts)
    text = NOISE_TOKEN_RE.sub('', text)

    # 12. "II " roman numeral artefact used as repeat marker (not a real word)
    text = re.sub(r'\bII\s+', '', text)

    # 13. "0 - rang" → "orang" (OCR misread: '0' for 'o' when "o-rang" is syllabified)
    text = re.sub(r'\b0\s*-\s*rang\b', 'orang', text)

    # 14. "sebabla" / "sebab la" → "sebab Ia"  (fused OCR)
    text = re.sub(r'\bsebabla\b', 'sebab Ia', text, flags=re.IGNORECASE)
    text = re.sub(r'\bsebab\s+la\b', 'sebab Ia', text, flags=re.IGNORECASE)

    # 15. Trailing " - - Nya" style artifacts → "Nya"
    text = re.sub(r'\s*(?:-\s*)+Nya\b', 'Nya', text)

    # 16. Stray trailing " - " or "- -" at end of text
    text = re.sub(r'[\s\-]+$', '', text)

    # 13. Trailing orphan words from noisy images (e.g. "Jan" at end after Gaya strip)
    # Nothing aggressive — just collapse multiple spaces and trim.

    # Final: normalize spaces, strip
    text = re.sub(r'  +', ' ', text)
    text = text.strip(' ,.')
    # Re-capitalize if first char was lowercased by cleanup
    if text and text[0].islower():
        text = text[0].upper() + text[1:]

    return text


def main():
    with open(REFRAINS_PATH, encoding='utf-8') as f:
        data: dict[str, str] = json.load(f)

    cleaned = {}
    removed = []
    for slug, raw in sorted(data.items()):
        # Check if entry is entirely notation noise
        if any(raw.startswith(p) for p in ENTIRELY_NOISE_PREFIXES):
            removed.append((slug, raw[:60]))
            continue

        text = clean(raw)

        # If result is too short or still looks like noise, drop it
        letters = sum(1 for c in text if c.isalpha())
        if letters < 8:
            removed.append((slug, f"[too short after clean] {raw[:60]}"))
            continue

        cleaned[slug] = text

    with open(REFRAINS_PATH, 'w', encoding='utf-8') as f:
        json.dump(cleaned, f, ensure_ascii=False, indent=2, sort_keys=True)

    print(f"✅  Cleaned {len(cleaned)} entries → {REFRAINS_PATH}")
    if removed:
        print(f"🗑️   Removed {len(removed)} entries:")
        for slug, reason in removed:
            print(f"    {slug}: {reason}")

    # Print a sample for visual inspection
    print("\n── Sample output ────────────────────────────────────────")
    for slug in [
        "a-minggu-adven-1", "a-hari-raya-santa-maria-bunda-allah",
        "a-minggu-prapaskah-3", "c-minggu-prapaskah-3", "a-minggu-palma",
        "a-vigili-pentakosta", "a-hari-raya-pentakosta",
        "a-minggu-biasa-8", "b-minggu-biasa-5", "a-minggu-biasa-16",
        "c-minggu-biasa-4", "b-minggu-biasa-29", "b-minggu-biasa-12",
        "a-malam-paskah-6", "a-kamis-putih", "a-hari-raya-paskah",
        "b-minggu-biasa-25", "c-minggu-biasa-20",
    ]:
        val = cleaned.get(slug, "(removed)")
        print(f"  {slug:<45} {val[:70]}")


if __name__ == "__main__":
    main()
