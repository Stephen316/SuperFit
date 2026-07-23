"""SuperFit Lite — Windows TDEE & macro calculator.

Same validated algorithms as the iOS app (docs/ALGORITHMS.md): Theil-Sen trend
slope over raw daily weights, energy-balance TDEE, confidence-weighted blend
with a Mifflin-St Jeor prior, guard-railed calorie targets, protein-first macros.
"""

import json
import statistics
import tkinter as tk
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from tkinter import messagebox, ttk

KCAL_PER_KG = 7700.0
WINDOW_DAYS = 30

ACTIVITY = {"Sedentary": 1.2, "Light": 1.375, "Moderate": 1.55, "Active": 1.725, "Athlete": 1.9}
GOALS = {"Fat loss": -0.20, "Recomposition": -0.10, "Maintenance": 0.0, "Muscle gain": 0.10}
PROTEIN_PER_KG = {"Fat loss": 2.0, "Recomposition": 2.0, "Maintenance": 1.8, "Muscle gain": 1.8}

DATA_DIR = Path.home() / "AppData" / "Roaming" / "SuperFitLite"
DATA_FILE = DATA_DIR / "data.json"


@dataclass
class Estimate:
    tdee: float
    confidence: float
    slope_per_week: float
    avg_intake: float
    days_used: int


def mifflin_bmr(sex, age, height_cm, weight_kg):
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    return base + {"Male": 5, "Female": -161}.get(sex, -78)


def theil_sen_slope(points):
    if len(points) < 2:
        return 0.0
    slopes = [
        (points[j][1] - points[i][1]) / (points[j][0] - points[i][0])
        for i in range(len(points))
        for j in range(i + 1, len(points))
        if points[j][0] != points[i][0]
    ]
    return statistics.median(slopes) if slopes else 0.0


def estimate_tdee(entries, sex, age, height_cm, activity_factor):
    if not entries:
        return None
    latest = max(date.fromisoformat(e["date"]) for e in entries)
    start = latest - timedelta(days=WINDOW_DAYS - 1)
    window = [e for e in entries if start <= date.fromisoformat(e["date"]) <= latest]

    weights = {}
    intakes = {}
    for e in window:
        day = (date.fromisoformat(e["date"]) - start).days
        if e.get("weight"):
            weights.setdefault(day, []).append(e["weight"])
        if e.get("kcal"):
            intakes[day] = intakes.get(day, 0) + e["kcal"]

    points = [(d, sum(ws) / len(ws)) for d, ws in sorted(weights.items())]
    slope = theil_sen_slope(points)
    avg_intake = sum(intakes.values()) / len(intakes) if intakes else 0.0
    raw_tdee = avg_intake - slope * KCAL_PER_KG

    coverage = len(intakes) / WINDOW_DAYS
    density = min(1.0, len(points) / (WINDOW_DAYS / 3))
    confidence = max(0.0, min(1.0, coverage * density))

    latest_weight = points[-1][1] if points else 75.0
    prior = mifflin_bmr(sex, age, height_cm, latest_weight) * activity_factor
    tdee = prior if not intakes else confidence * raw_tdee + (1 - confidence) * prior
    return Estimate(round(tdee), confidence, slope * 7, round(avg_intake), len(points))


def calorie_target(tdee, goal, weight_kg):
    raw = tdee * (1 + GOALS[goal])
    max_loss = weight_kg * 0.01 * KCAL_PER_KG / 7
    max_gain = weight_kg * 0.005 * KCAL_PER_KG / 7
    return round(max(tdee - max_loss, min(raw, tdee + max_gain)))


def macro_split(kcal, goal, weight_kg):
    protein = round(PROTEIN_PER_KG[goal] * weight_kg)
    fat = round(max(0.8 * weight_kg, 0.25 * kcal / 9))
    carbs = round(max(50, (kcal - 4 * protein - 9 * fat) / 4))
    return protein, fat, carbs


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("SuperFit Lite")
        self.geometry("640x600")
        self.minsize(560, 520)
        self.state_data = self.load()
        self.build()
        self.refresh_entries()
        self.recompute()

    def load(self):
        try:
            return json.loads(DATA_FILE.read_text())
        except (OSError, json.JSONDecodeError):
            return {"profile": {}, "entries": []}

    def save(self):
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        DATA_FILE.write_text(json.dumps(self.state_data, indent=1))

    def build(self):
        pad = {"padx": 8, "pady": 4}
        profile = self.state_data["profile"]

        pf = ttk.LabelFrame(self, text="Profile")
        pf.pack(fill="x", **pad)
        self.sex = tk.StringVar(value=profile.get("sex", "Male"))
        self.age = tk.StringVar(value=str(profile.get("age", 30)))
        self.height = tk.StringVar(value=str(profile.get("height", 175)))
        self.activity = tk.StringVar(value=profile.get("activity", "Moderate"))
        self.goal = tk.StringVar(value=profile.get("goal", "Recomposition"))

        for col, (label, var, values, width) in enumerate([
            ("Sex", self.sex, ["Male", "Female", "Other"], 8),
            ("Age", self.age, None, 5),
            ("Height cm", self.height, None, 6),
            ("Activity", self.activity, list(ACTIVITY), 10),
            ("Goal", self.goal, list(GOALS), 13),
        ]):
            ttk.Label(pf, text=label).grid(row=0, column=col, padx=6, pady=(4, 0), sticky="w")
            if values:
                w = ttk.Combobox(pf, textvariable=var, values=values, width=width, state="readonly")
            else:
                w = ttk.Entry(pf, textvariable=var, width=width)
            w.grid(row=1, column=col, padx=6, pady=(0, 6), sticky="w")
            var.trace_add("write", lambda *_: self.on_profile_change())

        ef = ttk.LabelFrame(self, text="Log a day")
        ef.pack(fill="x", **pad)
        self.entry_date = tk.StringVar(value=date.today().isoformat())
        self.entry_weight = tk.StringVar()
        self.entry_kcal = tk.StringVar()
        for col, (label, var, width) in enumerate([
            ("Date (YYYY-MM-DD)", self.entry_date, 12),
            ("Weight kg", self.entry_weight, 8),
            ("Calories eaten", self.entry_kcal, 10),
        ]):
            ttk.Label(ef, text=label).grid(row=0, column=col, padx=6, pady=(4, 0), sticky="w")
            ttk.Entry(ef, textvariable=var, width=width).grid(row=1, column=col, padx=6, pady=(0, 6), sticky="w")
        ttk.Button(ef, text="Add / update day", command=self.add_entry).grid(row=1, column=3, padx=6, pady=(0, 6))
        ttk.Label(ef, foreground="#666",
                  text="Only enter calories for days you logged everything you ate.").grid(
            row=2, column=0, columnspan=4, padx=6, pady=(0, 6), sticky="w")

        lf = ttk.LabelFrame(self, text="History")
        lf.pack(fill="both", expand=True, **pad)
        self.tree = ttk.Treeview(lf, columns=("date", "weight", "kcal"), show="headings", height=8)
        for cid, text, width in [("date", "Date", 110), ("weight", "Weight kg", 90), ("kcal", "Calories", 90)]:
            self.tree.heading(cid, text=text)
            self.tree.column(cid, width=width, anchor="center")
        self.tree.pack(side="left", fill="both", expand=True, padx=(6, 0), pady=6)
        scroll = ttk.Scrollbar(lf, orient="vertical", command=self.tree.yview)
        scroll.pack(side="left", fill="y", pady=6)
        self.tree.configure(yscrollcommand=scroll.set)
        ttk.Button(lf, text="Delete selected", command=self.delete_selected).pack(side="left", padx=6, anchor="n", pady=6)

        rf = ttk.LabelFrame(self, text="Your numbers")
        rf.pack(fill="x", **pad)
        self.result = tk.StringVar(value="Log a few days of weight and calories to begin.")
        ttk.Label(rf, textvariable=self.result, justify="left", font=("Segoe UI", 10)).pack(
            anchor="w", padx=8, pady=8)

    def on_profile_change(self):
        self.state_data["profile"] = {
            "sex": self.sex.get(),
            "age": self._num(self.age.get(), 30),
            "height": self._num(self.height.get(), 175),
            "activity": self.activity.get(),
            "goal": self.goal.get(),
        }
        self.save()
        self.recompute()

    @staticmethod
    def _num(text, default):
        try:
            return float(text)
        except ValueError:
            return default

    def add_entry(self):
        try:
            d = date.fromisoformat(self.entry_date.get().strip())
        except ValueError:
            messagebox.showerror("SuperFit Lite", "Date must be YYYY-MM-DD.")
            return
        if d > date.today():
            messagebox.showerror("SuperFit Lite", "Date is in the future.")
            return
        weight = self._num(self.entry_weight.get(), 0) or None
        kcal = self._num(self.entry_kcal.get(), 0) or None
        if weight is None and kcal is None:
            messagebox.showerror("SuperFit Lite", "Enter a weight, calories, or both.")
            return
        if weight is not None and not 30 <= weight <= 300:
            messagebox.showerror("SuperFit Lite", "Weight must be 30-300 kg.")
            return
        if kcal is not None and not 0 < kcal <= 10000:
            messagebox.showerror("SuperFit Lite", "Calories must be 1-10000.")
            return

        entries = [e for e in self.state_data["entries"] if e["date"] != d.isoformat()]
        entries.append({"date": d.isoformat(), "weight": weight, "kcal": kcal})
        entries.sort(key=lambda e: e["date"])
        self.state_data["entries"] = entries
        self.save()
        self.entry_weight.set("")
        self.entry_kcal.set("")
        self.refresh_entries()
        self.recompute()

    def delete_selected(self):
        selected = {self.tree.item(i, "values")[0] for i in self.tree.selection()}
        if not selected:
            return
        self.state_data["entries"] = [e for e in self.state_data["entries"] if e["date"] not in selected]
        self.save()
        self.refresh_entries()
        self.recompute()

    def refresh_entries(self):
        self.tree.delete(*self.tree.get_children())
        for e in reversed(self.state_data["entries"]):
            self.tree.insert("", "end", values=(
                e["date"],
                f"{e['weight']:.1f}" if e.get("weight") else "—",
                f"{e['kcal']:.0f}" if e.get("kcal") else "—",
            ))

    def recompute(self):
        entries = self.state_data["entries"]
        weights = [e["weight"] for e in entries if e.get("weight")]
        if not weights:
            self.result.set("Log a few days of weight and calories to begin.")
            return
        est = estimate_tdee(
            entries, self.sex.get(),
            self._num(self.age.get(), 30),
            self._num(self.height.get(), 175),
            ACTIVITY.get(self.activity.get(), 1.55))
        goal = self.goal.get()
        latest_weight = weights[-1]
        target = calorie_target(est.tdee, goal, latest_weight)
        protein, fat, carbs = macro_split(target, goal, latest_weight)

        lines = [
            f"Estimated TDEE: {est.tdee:.0f} kcal/day   (confidence {est.confidence:.0%})",
            f"Weight trend: {est.slope_per_week:+.2f} kg/week   ·   avg intake {est.avg_intake:.0f} kcal over {est.days_used} weigh-in days",
            f"Daily target for {goal.lower()}: {target} kcal",
            f"Macros: {protein} g protein · {fat} g fat · {carbs} g carbs",
        ]
        if est.confidence < 0.5:
            lines.append("Still learning — estimate leans on the formula until ~2 weeks of full logging.")
        self.result.set("\n".join(lines))


if __name__ == "__main__":
    App().mainloop()
