# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is

Two distinct parts live in this repository:

- **`BibleApp/` — the product.** An iOS-only SwiftUI app ("Lectio", a Catholic
  liturgical reading app). It is opened and run via `BibleApp/BibleApp.xcodeproj`
  in Xcode on **macOS** (simulator-only target, `SUPPORTED_PLATFORMS =
  iphonesimulator`). It has **no** CocoaPods/SPM dependencies. See
  `BibleApp/README.md` and `docs/` for details.
- **Python data-tooling scripts** (repo root `*.py`, `scripts/`,
  `BibleApp/scripts/`) — the offline pipeline that scrapes/cleans/converts the
  Bible + lectionary JSON that gets bundled into the iOS app.

### Platform limitation (important)

The Cursor Cloud VM is **Linux**. The iOS app **cannot be built or run here** —
there is no macOS, Xcode, or Swift toolchain (SwiftUI/UIKit/SwiftData are
unavailable on Linux). Do not attempt `xcodebuild`/`swift build` for the app;
build/run/UI verification of the app must be done on a Mac. On Linux you can
still edit Swift sources and work on the Python pipeline.

### Python environment (the runnable part on Linux)

- System Python is `3.12` and is **externally managed (PEP 668)** — install into
  the project venv, not system-wide.
- The startup update script creates/refreshes `.venv/` and installs
  `scripts/requirements.txt` (`requests`, `beautifulsoup4`, `pdfplumber`,
  `pypdf`). Run scripts with `.venv/bin/python`.
- `python3-venv` is a system package (already provisioned in the VM image); it is
  intentionally **not** in the update script.

### Running / testing the pipeline

- There is **no lint config and no automated test suite** in this repo. To
  sanity-check the Python scripts, byte-compile them:
  `.venv/bin/python -m py_compile *.py scripts/*.py BibleApp/scripts/*.py`.
- Many scripts (`enrich_*.py`, `scrape_*.py`, `convert_kitab_pdf_to_bible_json.py`)
  **require network access and/or large source PDFs** that are gitignored, so
  they cannot run fully offline.
- A good **offline, network-free** end-to-end check is the seed cleaner:
  `.venv/bin/python BibleApp/scripts/clean_tb_seed.py --input BibleApp/BibleApp/bible_seed.json --output /tmp/out.json --changes /tmp/changes.json --suspects /tmp/suspects.json`.
  It reads the bundled 5.8MB `bible_seed.json` (73 Catholic-canon books) and
  writes cleaned JSON in the same schema the app consumes.
- Write pipeline outputs to a temp dir (e.g. `/tmp/`); the checked-in
  `bible_seed.json` and other bundled JSON are the app's source of truth — don't
  overwrite them unless that is the actual task.
