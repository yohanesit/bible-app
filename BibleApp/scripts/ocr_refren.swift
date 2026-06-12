#!/usr/bin/env swift
// ocr_refren.swift — extract psalm refrain lyrics from a lagumisa image
// Usage: swift ocr_refren.swift /path/to/001.png

import Vision
import CoreImage
import Foundation

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift ocr_refren.swift <image_path>"); exit(1)
}

let ciImage = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
let handler = VNImageRequestHandler(ciImage: ciImage)
let request = VNRecognizeTextRequest()
request.recognitionLevel       = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages   = ["id-ID", "en-US"]
try! handler.perform([request])

struct Frag { let text: String; let x, y: CGFloat }

// ── Collect all fragments ──────────────────────────────────────────────────
var frags: [Frag] = []
for obs in request.results ?? [] {
    guard let t = obs.topCandidates(1).first?.string else { continue }
    frags.append(Frag(text: t, x: obs.boundingBox.minX, y: obs.boundingBox.minY))
}

// ── Classify helpers ───────────────────────────────────────────────────────

/// Count letter vs digit characters
func letterCount(_ s: String) -> Int {
    s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
}
func digitCount(_ s: String) -> Int {
    s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
}

/// A fragment is a lyric if it has at least 2 letters AND letters:digits > 2:1
func isLyric(_ s: String) -> Bool {
    let l = letterCount(s), d = digitCount(s)
    return l >= 2 && l > d * 2
}

/// Title line: "001 MARI KITA PERGI"
func isTitle(_ s: String) -> Bool {
    s.range(of: #"^\d{3}\s+"#, options: .regularExpression) != nil
}

/// Key/tempo annotation: "Do = As, 4/4" or "La = A, 2/4 gaya Lampung"
func isKeyLine(_ s: String) -> Bool {
    let l = s.lowercased()
    return l.hasPrefix("do =") || l.hasPrefix("la =") || l.hasPrefix("do=") || l.hasPrefix("la=")
}

// ── Keep only lyric fragments ──────────────────────────────────────────────
let lyrics = frags.filter { !isTitle($0.text) && !isKeyLine($0.text) && isLyric($0.text) }

// ── Group into y-bands (each band = one row of lyrics), sort left→right ───
let byY = lyrics.sorted { $0.y > $1.y }   // top → bottom

var bands: [[Frag]] = []
var band: [Frag] = []
var lastY: CGFloat = -1

for frag in byY {
    if lastY < 0 || abs(frag.y - lastY) < 0.07 {
        band.append(frag)
        lastY = (lastY < 0) ? frag.y : (lastY * 0.7 + frag.y * 0.3)
    } else {
        if !band.isEmpty { bands.append(band) }
        band = [frag]; lastY = frag.y
    }
}
if !band.isEmpty { bands.append(band) }

// Each band sorted left → right
let lines = bands.map { b in
    b.sorted { $0.x < $1.x }.map { $0.text }.joined(separator: " ")
}

// ── Join multi-system lines, handling cross-line syllable breaks ───────────
// If a line ends with "word-", the next line starts with the rest of that word
var joined = ""
for (i, line) in lines.enumerated() {
    if i == 0 {
        joined = line
    } else {
        // If previous line ends with a trailing hyphen syllable, no space
        if joined.hasSuffix("-") {
            joined = String(joined.dropLast()) + line  // remove hyphen, join directly
        } else {
            joined += " " + line
        }
    }
}

// ── Clean sheet-music syllabification markers ──────────────────────────────
// "word - word" (melodic gap) → "wordword"
// "syl-la-ble"  (syllable break) → "syllable"
// "syl- la"     (break across space) → "sylla"
var result = joined

// "X - Y" where X and Y are letter chars (musical gap marker) → "XY"
result = result.replacingOccurrences(of: #"([A-Za-z']) - ([A-Za-z'])"#,
                                      with: "$1$2", options: .regularExpression)
// Repeat once to catch chains like "A - B - C"
result = result.replacingOccurrences(of: #"([A-Za-z']) - ([A-Za-z'])"#,
                                      with: "$1$2", options: .regularExpression)

// "X-Y" syllable hyphens → "XY"
result = result.replacingOccurrences(of: #"([A-Za-z'])-([A-Za-z'])"#,
                                      with: "$1$2", options: .regularExpression)
// Repeat for triple hyphens like "su-ka-ci-ta"
result = result.replacingOccurrences(of: #"([A-Za-z'])-([A-Za-z'])"#,
                                      with: "$1$2", options: .regularExpression)

// "X- Y" (syllable continues across a space to next fragment) → "XY"
result = result.replacingOccurrences(of: #"([A-Za-z'])- ([A-Za-z'])"#,
                                      with: "$1$2", options: .regularExpression)

// Normalize spaces
result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
// Strip any leading "- " artifact (fragment starting mid-word at line beginning)
result = result.replacingOccurrences(of: #"^- "#, with: "", options: .regularExpression)
result = result.trimmingCharacters(in: .whitespacesAndNewlines)

print(result)
