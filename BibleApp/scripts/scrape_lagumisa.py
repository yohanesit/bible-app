#!/usr/bin/env python3
"""
scrape_lagumisa.py
==================
Scrapes responsorial psalm refrains from lagumisa.web.id and outputs
lagumisa_refrains.json, which is bundled with the iOS app.

The psalm refrain (antiphon/ulangan) for each occasion is displayed as a sheet
music image on lagumisa. This script:
  1. Fetches each occasion page to find the refren image number
  2. Downloads the sheet music PNG
  3. OCRs it using macOS Vision (via a compiled Swift binary) to extract the lyric line
  4. Writes slug → refrain text to lagumisa_refrains.json

Prerequisites:
  - macOS with Xcode installed (for swiftc)
  - The OCR helper is auto-compiled on first run

Only occasion-based slugs are scraped (a-*, b-*, c-*, p-*).
Numeric slugs (001, 002, …) are generic psalm pages, not occasion-specific.

Usage:
    python3 scripts/scrape_lagumisa.py

Output:
    BibleApp/BibleApp/lagumisa_refrains.json
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

BASE_URL = "https://www.lagumisa.web.id"
PAGE_URL  = f"{BASE_URL}/lagumz.php?&f={{slug}}"

# All occasion-based slugs harvested from mazmur.php (a-*, b-*, c-*, p-*)
# Numeric slugs (001–190, 801–868, 951–966) are generic psalm pages, not used.
OCCASION_SLUGS = [
    "a-minggu-adven-1", "b-minggu-adven-1", "c-minggu-adven-1",
    "a-minggu-adven-2", "b-minggu-adven-2", "c-minggu-adven-2",
    "a-minggu-adven-3", "b-minggu-adven-3", "c-minggu-adven-3",
    "a-minggu-adven-4", "b-minggu-adven-4", "c-minggu-adven-4",
    "a-hari-raya-natal-sore", "a-hari-raya-natal-malam",
    "a-hari-raya-natal-fajar", "a-hari-raya-natal-siang",
    "a-pesta-keluarga-kudus-yesus-maria-yusuf",
    "b-pesta-keluarga-kudus-yesus-maria-yusuf",
    "c-pesta-keluarga-kudus-yesus-maria-yusuf",
    "a-hari-raya-santa-maria-bunda-allah",
    "a-hari-raya-penampakan-tuhan",
    "a-pesta-pembaptisan-tuhan", "b-pesta-pembaptisan-tuhan", "c-pesta-pembaptisan-tuhan",
    "a-rabu-abu", "b-rabu-abu", "c-rabu-abu",
    "a-minggu-prapaskah-1", "b-minggu-prapaskah-1", "c-minggu-prapaskah-1",
    "a-minggu-prapaskah-2", "b-minggu-prapaskah-2", "c-minggu-prapaskah-2",
    "a-minggu-prapaskah-3", "b-minggu-prapaskah-3", "c-minggu-prapaskah-3",
    "a-minggu-prapaskah-4", "b-minggu-prapaskah-4", "c-minggu-prapaskah-4",
    "a-minggu-prapaskah-5", "b-minggu-prapaskah-5", "c-minggu-prapaskah-5",
    "a-minggu-palma",
    "a-kamis-dalam-pekan-suci",
    "a-kamis-putih",
    "a-jumat-agung",
    "a-malam-paskah-1a", "a-malam-paskah-1b", "a-malam-paskah-2",
    "a-malam-paskah-3", "a-malam-paskah-4", "a-malam-paskah-5",
    "a-malam-paskah-6", "a-malam-paskah-7a", "a-malam-paskah-7b",
    "a-malam-paskah-8",
    "a-hari-raya-paskah",
    "a-madah-paskah",
    "a-minggu-paskah-2", "b-minggu-paskah-2", "c-minggu-paskah-2",
    "a-minggu-paskah-3", "b-minggu-paskah-3", "c-minggu-paskah-3",
    "a-minggu-paskah-4", "b-minggu-paskah-4", "c-minggu-paskah-4",
    "a-minggu-paskah-5", "b-minggu-paskah-5", "c-minggu-paskah-5",
    "a-minggu-paskah-6", "b-minggu-paskah-6", "c-minggu-paskah-6",
    "a-hari-raya-kenaikan",
    "a-minggu-paskah-7", "b-minggu-paskah-7", "c-minggu-paskah-7",
    "a-vigili-pentakosta",
    "a-hari-raya-pentakosta",
    "a-madah-pentakosta",
    "a-minggu-biasa-2",  "b-minggu-biasa-2",  "c-minggu-biasa-2",
    "a-minggu-biasa-3",  "b-minggu-biasa-3",  "c-minggu-biasa-3",
    "a-minggu-biasa-4",  "b-minggu-biasa-4",  "c-minggu-biasa-4",
    "a-minggu-biasa-5",  "b-minggu-biasa-5",  "c-minggu-biasa-5",
    "a-minggu-biasa-6",  "b-minggu-biasa-6",  "c-minggu-biasa-6",
    "a-minggu-biasa-7",  "b-minggu-biasa-7",  "c-minggu-biasa-7",
    "a-minggu-biasa-8",  "b-minggu-biasa-8",  "c-minggu-biasa-8",
    "a-minggu-biasa-9",  "b-minggu-biasa-9",  "c-minggu-biasa-9",
    "a-minggu-biasa-10", "b-minggu-biasa-10", "c-minggu-biasa-10",
    "a-minggu-biasa-11", "b-minggu-biasa-11", "c-minggu-biasa-11",
    "a-minggu-biasa-12", "b-minggu-biasa-12", "c-minggu-biasa-12",
    "a-minggu-biasa-13", "b-minggu-biasa-13", "c-minggu-biasa-13",
    "a-minggu-biasa-14", "b-minggu-biasa-14", "c-minggu-biasa-14",
    "a-minggu-biasa-15", "b-minggu-biasa-15", "c-minggu-biasa-15",
    "a-minggu-biasa-16", "b-minggu-biasa-16", "c-minggu-biasa-16",
    "a-minggu-biasa-17", "b-minggu-biasa-17", "c-minggu-biasa-17",
    "a-minggu-biasa-18", "b-minggu-biasa-18", "c-minggu-biasa-18",
    "a-minggu-biasa-19", "b-minggu-biasa-19", "c-minggu-biasa-19",
    "a-minggu-biasa-20", "b-minggu-biasa-20", "c-minggu-biasa-20",
    "a-minggu-biasa-21", "b-minggu-biasa-21", "c-minggu-biasa-21",
    "a-minggu-biasa-22", "b-minggu-biasa-22", "c-minggu-biasa-22",
    "a-minggu-biasa-23", "b-minggu-biasa-23", "c-minggu-biasa-23",
    "a-minggu-biasa-24", "b-minggu-biasa-24", "c-minggu-biasa-24",
    "a-minggu-biasa-25", "b-minggu-biasa-25", "c-minggu-biasa-25",
    "a-minggu-biasa-26", "b-minggu-biasa-26", "c-minggu-biasa-26",
    "a-minggu-biasa-27", "b-minggu-biasa-27", "c-minggu-biasa-27",
    "a-minggu-biasa-28", "b-minggu-biasa-28", "c-minggu-biasa-28",
    "a-minggu-biasa-29", "b-minggu-biasa-29", "c-minggu-biasa-29",
    "a-minggu-biasa-30", "b-minggu-biasa-30", "c-minggu-biasa-30",
    "a-minggu-biasa-31", "b-minggu-biasa-31", "c-minggu-biasa-31",
    "a-minggu-biasa-32", "b-minggu-biasa-32", "c-minggu-biasa-32",
    "a-minggu-biasa-33", "b-minggu-biasa-33", "c-minggu-biasa-33",
    "a-minggu-biasa-34-hr-kristus-raja",
    "b-minggu-biasa-34-hr-kristus-raja",
    "c-minggu-biasa-34-hr-kristus-raja",
    "a-hari-raya-tritunggal-mahakudus",
    "b-hari-raya-tritunggal-mahakudus",
    "c-hari-raya-tritunggal-mahakudus",
    "a-hari-raya-tubuh-dan-darah-kristus",
    "b-hari-raya-tubuh-dan-darah-kristus",
    "c-hari-raya-tubuh-dan-darah-kristus",
    "a-madah-ekaristi",
    "a-hari-raya-hati-yesus-yang-mahakudus",
    "b-hari-raya-hati-yesus-yang-mahakudus",
    "c-hari-raya-hati-yesus-yang-mahakudus",
    "p-pesta-bertobatnya-st-paulus",
    "p-pesta-yesus-dipersembahkan-di-kenisah",
    "p-hari-raya-st-yusuf",
    "p-hari-raya-kabar-sukacita",
    "p-pesta-stmarkus",
    "p-pesta-stfilipus-dan-styakobus",
    "p-pesta-stmatias",
    "p-pesta-stmaria-mengunjungi-elizabet",
    "p-hari-raya-kelahiran-st-yohanes-pembaptis",
    "p-hari-raya-st-petrus-dan-paulus",
    "p-pesta-stthomas",
    "p-pesta-styakobus",
    "p-pesta-yesus-menampakkan-kemuliaannya",
    "p-pesta-stlaurensius",
    "p-hari-raya-spmaria-diangkat-ke-surga",
    "p-hari-raya-kemerdekaan",
    "p-pesta-stbartolomeus",
    "p-pesta-kelahiran-spmaria",
    "p-pesta-salib-suci",
    "p-pesta-st-matius-rasul-dan-pengarang-injil",
    "p-pesta-stmikael-gabriel-rafael",
    "p-pesta-stteresia-dari-kanak-kanak-yesus",
    "p-peringatan-stfransiskus-asisi",
    "p-pesta-stlukas",
    "p-pesta-stsimon-yudas",
    "p-hari-raya-semua-orang-kudus",
    "p-peringatan-arwah-semua-orang-beriman",
    "p-pesta-pemberkatan-gereja-basilik-lateran",
    "p-pesta-standreas",
    "p-pesta-stfransiskus-xaverius",
    "p-hari-raya-spmaria-dikandung-tanpa-dosa",
    "p-pesta-ststefanus",
    "p-pesta-styohanes",
    "p-pesta-kanak-kanak-suci",
]

OUTPUT_PATH = Path(__file__).parent.parent / "BibleApp" / "lagumisa_refrains.json"

HEADERS       = {"User-Agent": "Mozilla/5.0 (compatible; BibleApp-scraper/1.0)"}
DELAY_SECONDS = 0.5   # be polite to the server
IMAGE_BASE    = f"{BASE_URL}/f85333c6-886f-4a59-811a-c192b255fcf2/mz"

# Path to the compiled OCR binary (auto-built on first run)
SCRIPT_DIR  = Path(__file__).parent
OCR_SRC     = SCRIPT_DIR / "ocr_refren.swift"
OCR_BINARY  = SCRIPT_DIR / "ocr_refren"


# ---------------------------------------------------------------------------
# OCR binary setup
# ---------------------------------------------------------------------------

OCR_SWIFT_SOURCE = r'''
import Vision
import CoreImage
import Foundation

guard CommandLine.arguments.count > 1 else { print(""); exit(0) }

let ciImage = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
let handler = VNImageRequestHandler(ciImage: ciImage)
let request = VNRecognizeTextRequest()
request.recognitionLevel       = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages   = ["id-ID", "en-US"]
try! handler.perform([request])

struct Frag { let text: String; let x, y: CGFloat }

var frags: [Frag] = []
for obs in request.results ?? [] {
    guard let t = obs.topCandidates(1).first?.string else { continue }
    frags.append(Frag(text: t, x: obs.boundingBox.minX, y: obs.boundingBox.minY))
}

func letterCount(_ s: String) -> Int { s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count }
func digitCount(_ s: String) -> Int  { s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count }
func isLyric(_ s: String) -> Bool    { let l = letterCount(s), d = digitCount(s); return l >= 2 && l > d * 2 }
func isTitle(_ s: String) -> Bool    { s.range(of: #"^\d{3}\s+"#, options: .regularExpression) != nil }
func isKeyLine(_ s: String) -> Bool  { let l = s.lowercased(); return l.hasPrefix("do =") || l.hasPrefix("la =") || l.hasPrefix("do=") || l.hasPrefix("la=") }

let lyrics = frags.filter { !isTitle($0.text) && !isKeyLine($0.text) && isLyric($0.text) }
let byY    = lyrics.sorted { $0.y > $1.y }

var bands: [[Frag]] = []; var band: [Frag] = []; var lastY: CGFloat = -1
for frag in byY {
    if lastY < 0 || abs(frag.y - lastY) < 0.07 {
        band.append(frag); lastY = (lastY < 0) ? frag.y : (lastY * 0.7 + frag.y * 0.3)
    } else { if !band.isEmpty { bands.append(band) }; band = [frag]; lastY = frag.y }
}
if !band.isEmpty { bands.append(band) }

let lines = bands.map { b in b.sorted { $0.x < $1.x }.map { $0.text }.joined(separator: " ") }

var joined = ""
for (i, line) in lines.enumerated() {
    if i == 0 { joined = line }
    else if joined.hasSuffix("-") { joined = String(joined.dropLast()) + line }
    else { joined += " " + line }
}

var result = joined
result = result.replacingOccurrences(of: #"([A-Za-z']) - ([A-Za-z'])"#, with: "$1$2", options: .regularExpression)
result = result.replacingOccurrences(of: #"([A-Za-z']) - ([A-Za-z'])"#, with: "$1$2", options: .regularExpression)
result = result.replacingOccurrences(of: #"([A-Za-z'])-([A-Za-z'])"#,   with: "$1$2", options: .regularExpression)
result = result.replacingOccurrences(of: #"([A-Za-z'])-([A-Za-z'])"#,   with: "$1$2", options: .regularExpression)
result = result.replacingOccurrences(of: #"([A-Za-z'])- ([A-Za-z'])"#,  with: "$1$2", options: .regularExpression)
result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
result = result.replacingOccurrences(of: #"^- "#,    with: "",  options: .regularExpression)
print(result.trimmingCharacters(in: .whitespacesAndNewlines))
'''

def ensure_ocr_binary():
    """Compile the Swift OCR helper if not already built or source changed."""
    if not OCR_SRC.exists():
        OCR_SRC.write_text(OCR_SWIFT_SOURCE)
    needs_build = (
        not OCR_BINARY.exists()
        or OCR_SRC.stat().st_mtime > OCR_BINARY.stat().st_mtime
    )
    if needs_build:
        print("Compiling OCR helper (first run)…")
        subprocess.run(
            ["swiftc", str(OCR_SRC), "-o", str(OCR_BINARY), "-O"],
            check=True
        )
        print("OCR helper compiled ✓\n")


# ---------------------------------------------------------------------------
# Fetch helpers
# ---------------------------------------------------------------------------

def fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read()

def fetch_html(url: str) -> str:
    return fetch_bytes(url).decode("utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Refrain extraction via image OCR
# ---------------------------------------------------------------------------

def extract_refren_number(html: str):
    """Extract the refren image number from the page header, e.g. 'Refren 001' → '001'."""
    m = re.search(r'Refren\s+(\d{3})', html)
    return m.group(1) if m else None

def ocr_image(image_bytes: bytes) -> str:
    """Run the compiled OCR binary on image bytes, return extracted lyric string."""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        f.write(image_bytes)
        tmp_path = f.name
    try:
        result = subprocess.run(
            [str(OCR_BINARY), tmp_path],
            capture_output=True, text=True, timeout=15
        )
        return result.stdout.strip()
    finally:
        os.unlink(tmp_path)

def extract_refrain(html: str):
    """
    Extract the sung psalm refrain for this occasion page.
    Strategy: find the refren image number in the header, download the PNG,
    OCR the lyric line from the sheet music image.
    """
    refren_num = extract_refren_number(html)
    if not refren_num:
        return None
    image_url = f"{IMAGE_BASE}/{refren_num}.png"
    try:
        image_bytes = fetch_bytes(image_url)
    except Exception:
        return None
    text = ocr_image(image_bytes)
    return text if text else None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    ensure_ocr_binary()

    slugs = OCCASION_SLUGS
    print(f"Scraping {len(slugs)} occasion-based slugs.\n")

    results = {}
    failed  = []

    for i, slug in enumerate(slugs, 1):
        url = PAGE_URL.format(slug=slug)
        try:
            html    = fetch_html(url)
            refrain = extract_refrain(html)
            if refrain:
                results[slug] = refrain
                preview = refrain[:60] + ("…" if len(refrain) > 60 else "")
                status  = f"OK  {preview}"
            else:
                failed.append(slug)
                status = "SKIP (no refrain found)"
        except Exception as exc:
            failed.append(slug)
            status = f"ERROR: {exc}"

        print(f"[{i:3}/{len(slugs)}] {slug:<50} {status}")
        time.sleep(DELAY_SECONDS)

    # Write output
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2, sort_keys=True)

    print(f"\n✅  Wrote {len(results)} refrains → {OUTPUT_PATH}")
    if failed:
        print(f"⚠️   {len(failed)} slugs had no refrain:")
        for s in failed:
            print(f"    {s}")


if __name__ == "__main__":
    main()
