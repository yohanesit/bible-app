#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path


UNICODE_SPACES = [
    ("\u00a0", " "),
    ("\u2009", " "),
    ("\u202f", " "),
    ("\u2007", " "),
]


def normalize_spaces(text: str) -> str:
    s = text
    for src, dst in UNICODE_SPACES:
        s = s.replace(src, dst)
    s = re.sub(r" {2,}", " ", s)
    return s.strip()


def collapse_spaced_letters(text: str) -> str:
    # Collapse OCR fragments like "S e l a" -> "Sela".
    return re.sub(r"\b(?:[A-Za-z]\s){2,}[A-Za-z]\b", lambda m: m.group(0).replace(" ", ""), text)


def repair_hyphenated_words(text: str) -> str:
    # "me- lihat" -> "melihat"
    return re.sub(r"\b([A-Za-z]{1,3})-\s+([a-z]{2,})\b", r"\1\2", text)


def verse_is_suspicious(text: str) -> list[str]:
    reasons: list[str] = []
    tokens = re.findall(r"[A-Za-zÀ-ÿ]+", text)
    if tokens:
        short_ratio = sum(1 for t in tokens if len(t) <= 2) / len(tokens)
        if len(tokens) >= 8 and short_ratio >= 0.35:
            reasons.append(f"high_short_token_ratio:{short_ratio:.2f}")
    if re.search(r"\b(?:[A-Za-z]\s){3,}[A-Za-z]\b", text):
        reasons.append("spaced_letter_run")
    if re.search(r"\b[A-Za-z]{1,3}-\s*$", text):
        reasons.append("dangling_hyphen_end")
    if re.search(r"(^|[.!?]\s)([A-Z][a-z]{1,3})\s+[a-z]{3,}\b", text):
        reasons.append("possible_sentence_split")
    return reasons


def is_safe_continuation(text: str) -> bool:
    stripped = text.lstrip()
    if not stripped:
        return False
    first = re.match(r"[A-Za-z]+", stripped)
    if not first:
        return False
    token = first.group(0)
    # Hyphen continuations from line wraps should continue with lowercase.
    return token[:1].islower()


def stitch_verse_boundary(prev_text: str, curr_text: str) -> tuple[str, str, bool]:
    # Join "Allah me-" + "lihat ..." => "Allah melihat ..."
    m = re.search(r"\b([A-Za-z]{1,8})-\s*$", prev_text)
    if not m:
        return prev_text, curr_text, False
    curr = curr_text.lstrip()
    first = re.match(r"([A-Za-z]{2,})(.*)$", curr)
    if not first:
        return prev_text, curr_text, False
    cont = first.group(1)
    rest = first.group(2)
    if not is_safe_continuation(curr_text):
        m2 = re.match(r"\s*(Ia|ia|Dan|dan)\s+([a-z]{2,})(.*)$", curr_text)
        if m2:
            cont = m2.group(2)
            rest = m2.group(3)
            if m2.group(1).lower() == "ia":
                rest = re.sub(r"\.\s+tidak\b", ". Ia tidak", rest, count=1)
        else:
            # Common OCR split:
            # prev "...be-" + curr "Se berapa ... . gala sesuatu ..."
            # -> prev "...beberapa", curr "orang ... . Segala sesuatu ..."
            m3 = re.match(r"\s*([A-Z][a-z]{1,4})\s+([a-z]{2,})(.*)$", curr_text)
            if not m3:
                return prev_text, curr_text, False
            prefix = m3.group(1)
            cont = m3.group(2)
            rest = m3.group(3).lstrip()
            rest = re.sub(
                r"\.\s+([a-z]{1,4})\s+",
                lambda mm: f". {(prefix + mm.group(1)).capitalize()} ",
                rest,
                count=1,
            )
    fixed_prev = prev_text[: m.start(1)] + m.group(1) + cont
    fixed_curr = rest.lstrip()
    return fixed_prev, fixed_curr, True


def fix_known_genesis_glitch(book: str, chapter: str, verse_num: int, text: str) -> tuple[str, bool]:
    if book == "kej" and chapter == "1" and verse_num == 17:
        fixed = text
        fixed = fixed.replace("Allah tang-bintang. menaruh semuanya", "Allah menaruh semuanya")
        fixed = fixed.replace("menaruh semuanya tang-bintang itu", "menaruh semuanya itu")
        return fixed, fixed != text
    if book == "kej" and chapter == "1" and verse_num == 18:
        fixed = text.replace("Allah me-", "Allah melihat")
        return fixed, fixed != text
    if book == "kej" and chapter == "1" and verse_num == 19:
        fixed = text
        fixed = re.sub(r"^Ja\s+lihat\s+bahwa", "bahwa", fixed)
        fixed = fixed.replace("Allah melihat bahwa bahwa", "bahwa")
        fixed = fixed.replace("dilah petang", "Jadilah petang")
        return fixed, fixed != text
    return text, False


def main() -> None:
    parser = argparse.ArgumentParser(description="Clean TB seed JSON from PDF/OCR artifacts")
    parser.add_argument("--input", required=True, help="Path to input bible_seed.json")
    parser.add_argument("--output", required=True, help="Path to cleaned bible_seed.json")
    parser.add_argument("--changes", required=True, help="Path to JSON report for changed verses")
    parser.add_argument("--suspects", required=True, help="Path to JSON report for suspicious verses")
    args = parser.parse_args()

    in_path = Path(args.input)
    out_path = Path(args.output)
    changes_path = Path(args.changes)
    suspects_path = Path(args.suspects)

    seed = json.loads(in_path.read_text(encoding="utf-8"))
    books = seed.get("books", {})

    changes: list[dict] = []
    suspects: list[dict] = []

    for book, chapters in books.items():
        for chapter, verses in chapters.items():
            for i, verse in enumerate(verses):
                old = verse.get("t", "")
                new = old

                new = normalize_spaces(new)
                new = collapse_spaced_letters(new)
                new = repair_hyphenated_words(new)
                new, touched_known = fix_known_genesis_glitch(book, chapter, verse.get("v"), new)

                if i > 0:
                    prev = verses[i - 1]
                    p_old = prev.get("t", "")
                    p_new, c_new, stitched = stitch_verse_boundary(p_old, new)
                    if stitched:
                        prev["t"] = p_new
                        new = c_new
                        changes.append(
                            {
                                "book": book,
                                "chapter": chapter,
                                "verse": prev.get("v"),
                                "type": "cross_verse_stitch_prev",
                                "before": p_old,
                                "after": p_new,
                            }
                        )

                if new != old:
                    verse["t"] = new
                    changes.append(
                        {
                            "book": book,
                            "chapter": chapter,
                            "verse": verse.get("v"),
                            "type": "known_patch" if touched_known else "normalized",
                            "before": old,
                            "after": new,
                        }
                    )

                reasons = verse_is_suspicious(verse.get("t", ""))
                if reasons:
                    suspects.append(
                        {
                            "book": book,
                            "chapter": chapter,
                            "verse": verse.get("v"),
                            "reasons": reasons,
                            "text": verse.get("t", ""),
                        }
                    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    changes_path.parent.mkdir(parents=True, exist_ok=True)
    suspects_path.parent.mkdir(parents=True, exist_ok=True)

    out_path.write_text(
        json.dumps(seed, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    changes_path.write_text(json.dumps(changes, ensure_ascii=False, indent=2), encoding="utf-8")
    suspects_path.write_text(json.dumps(suspects, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Changed verses: {len(changes)}")
    print(f"Suspicious verses: {len(suspects)}")
    print(f"Cleaned seed: {out_path}")
    print(f"Changes report: {changes_path}")
    print(f"Suspects report: {suspects_path}")


if __name__ == "__main__":
    main()
