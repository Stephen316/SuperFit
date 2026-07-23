"""Builds ios/SuperFit/Resources/fdc_seed.json from USDA FoodData Central
public-domain datasets (Foundation + SR Legacy) so the app ships every generic
whole food offline, with no API key.

Usage: python tools/build_fdc_seed.py [work_dir]
Downloads the zips into work_dir (default .fdc_cache/) unless already present.
"""

import csv
import io
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

DATASETS = {
    "foundation": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2025-04-24.zip",
    "sr_legacy": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip",
}

# FDC nutrient ids: energy kcal, protein, fat, carbohydrate by difference, fibre
NUTRIENTS = {1008: "k", 1003: "p", 1004: "f", 1005: "c", 1079: "b"}

OUT = Path(__file__).resolve().parent.parent / "ios" / "SuperFit" / "Resources" / "fdc_seed.json"


def fetch(url, dest):
    if dest.exists():
        return
    print(f"downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "SuperFit-build/1.0"})
    dest.write_bytes(urllib.request.urlopen(req, timeout=300).read())


def read_csv(zf, name):
    with zf.open(name) as fh:
        yield from csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8-sig"))


def extract(zip_path, source):
    foods = {}
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        food_csv = next(n for n in names if n.endswith("/food.csv"))
        nutrient_csv = next(n for n in names if n.endswith("/food_nutrient.csv"))

        for row in read_csv(zf, food_csv):
            desc = row["description"].strip()
            if not desc:
                continue
            foods[row["fdc_id"]] = {"i": int(row["fdc_id"]), "n": desc, "s": source}

        for row in read_csv(zf, nutrient_csv):
            food = foods.get(row["fdc_id"])
            key = NUTRIENTS.get(int(float(row["nutrient_id"])))
            if food is None or key is None or not row["amount"]:
                continue
            food[key] = round(float(row["amount"]), 2)
    return [f for f in foods.values() if "k" in f]


def main():
    work = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".fdc_cache")
    work.mkdir(exist_ok=True)

    all_foods = []
    for source, url in DATASETS.items():
        zip_path = work / f"{source}.zip"
        fetch(url, zip_path)
        foods = extract(zip_path, source)
        print(f"{source}: {len(foods)} foods with energy data")
        all_foods.extend(foods)

    # Foundation entries are lab-analyzed and fresher: when the same description
    # exists in both sets, keep Foundation.
    by_name = {}
    for f in sorted(all_foods, key=lambda f: f["s"] != "foundation"):
        by_name.setdefault(f["n"].lower(), f)
    final = sorted(by_name.values(), key=lambda f: f["n"].lower())
    for f in final:
        f.pop("s")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(final, separators=(",", ":"), ensure_ascii=False),
                   encoding="utf-8")
    print(f"wrote {len(final)} foods -> {OUT} ({OUT.stat().st_size / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()
