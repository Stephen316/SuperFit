# SuperFit Lite (Windows)

Standalone Windows calculator using the same validated adaptive-TDEE and macro
algorithms as the iOS app (see [docs/ALGORITHMS.md](../docs/ALGORITHMS.md)).

Download the `.exe` from the repo's **Releases** page — no install needed.

Windows SmartScreen may warn about an unrecognized app (the binary is unsigned);
choose "More info → Run anyway".

## What it does
Log your weight and calories day by day; it measures your real TDEE from the
trend (Theil-Sen slope × 7700 kcal/kg energy balance), then gives an adaptive
calorie target and macro split for your goal. Data stays local in
`%APPDATA%\SuperFitLite\data.json`.

## Run from source
```
python superfit_lite.py
```
Needs Python 3.10+, no third-party packages (tkinter is in the standard library).

## Build the exe
```
pip install pyinstaller
pyinstaller --onefile --windowed --name SuperFitLite superfit_lite.py
```
Output: `dist\SuperFitLite.exe`. Publish with:
```
gh release create v0.1.0 dist/SuperFitLite.exe --title "SuperFit Lite v0.1.0"
```
