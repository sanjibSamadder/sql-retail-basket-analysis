"""Builds README charts from the CSVs exported by sql/10_export_and_priorities.sql.
Run from the project root:  python3 python/make_charts.py
"""
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path

Path("images").mkdir(exist_ok=True)
plt.rcParams.update({"figure.dpi": 150, "axes.spines.top": False,
                     "axes.spines.right": False, "font.size": 10})

# ---------------------------------------------------------------- 1. Retention heatmap
ret = pd.read_csv("results/cohort_retention.csv", parse_dates=["cohort_month"])
ret = ret[ret["cohort_size"] >= 100]
pivot = ret.pivot(index="cohort_month", columns="month_number", values="retention_pct")
pivot.index = pivot.index.strftime("%b %Y")

fig, ax = plt.subplots(figsize=(12, 3.4))
im = ax.imshow(pivot.values, aspect="auto", cmap="YlGnBu", vmin=0, vmax=100)
ax.set_xticks(range(len(pivot.columns)))
ax.set_xticklabels(pivot.columns)
ax.set_yticks(range(len(pivot.index)))
ax.set_yticklabels(pivot.index)
for i in range(pivot.shape[0]):
    for j in range(pivot.shape[1]):
        v = pivot.values[i, j]
        if pd.notna(v):
            ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=7,
                    color="white" if v > 60 else "black")
ax.set_xlabel("30-day period since first basket (0 = first 30 days)")
ax.set_title("Retention by enrollment cohort: % of households active in each period")
fig.colorbar(im, ax=ax, label="% active")
fig.tight_layout()
fig.savefig("images/01_retention_heatmap.png")
plt.close(fig)

# ---------------------------------------------------------------- 2. Cohort forest plot
cat = pd.read_csv("results/cohort_category_results.csv").sort_values("diff_visits")
sel = pd.concat([cat.head(12), cat.tail(12)])
n_tested = len(cat)
n_sig = int((cat["significant"] == "yes").sum())

fig, ax = plt.subplots(figsize=(9, 7))
ypos = list(range(len(sel)))
colors = ["#d95f02" if s == "yes" else "#6b6b6b" for s in sel["significant"]]
ax.errorbar(sel["diff_visits"], ypos, xerr=sel["ci95_visits"], fmt="none",
            ecolor="#c4c4c4", capsize=2, zorder=1)
ax.scatter(sel["diff_visits"], ypos, c=colors, zorder=2)
ax.axvline(0, color="black", lw=0.8)
ax.set_yticks(ypos)
ax.set_yticklabels(sel["category"].str.title().str.replace("Hbc","HBC").str.replace(" Mw"," MW"), fontsize=8)
ax.set_xlabel("Extra visits in 90 days vs. households with a similar-sized first basket (95% CI)")
ax.set_title(f"Does the first-basket category predict repeat visits?\n"
             f"{n_sig} of {n_tested} categories nominally significant (orange); "
             f"12 highest and 12 lowest shown", fontsize=10)
fig.tight_layout()
fig.savefig("images/02_cohort_category_effects.png")
plt.close(fig)

# ---------------------------------------------------------------- 3. Naive vs adjusted lift
pairs = pd.read_csv("results/category_pairs_adjusted.csv")
keys = [("BABY FOODS", "INFANT FORMULA"), ("CAT FOOD", "CAT LITTER"),
        ("BABY HBC", "DIAPERS & DISPOSABLES"), ("DRY NOODLES/PASTA", "PASTA SAUCE"),
        ("CHEESES", "DELI MEATS"), ("BAKED BREAD/BUNS/ROLLS", "HOT DOGS"),
        ("COLD CEREAL", "FLUID MILK PRODUCTS"), ("BAG SNACKS", "SOFT DRINKS"),
        ("BAKED BREAD/BUNS/ROLLS", "FLUID MILK PRODUCTS")]
want = {frozenset(k) for k in keys}
mask = pairs.apply(lambda r: frozenset((r["cat_a"], r["cat_b"])) in want, axis=1)
sub = pairs[mask].copy()
sub["label"] = sub["cat_a"].str.title().str.replace("Hbc","HBC").str.replace(" Mw"," MW") + " + " + sub["cat_b"].str.title().str.replace("Hbc","HBC").str.replace(" Mw"," MW")
sub = sub.sort_values("naive_lift").reset_index(drop=True)

fig, ax = plt.subplots(figsize=(10, 5.5))
h = 0.38
ys = list(range(len(sub)))
ax.barh([y + h / 2 for y in ys], sub["naive_lift"], height=h, color="#bdbdbd",
        label="Naive lift")
ax.barh([y - h / 2 for y in ys], sub["adj_lift"], height=h, color="#1b6ca8",
        label="Basket-size-adjusted lift")
for y, n, a in zip(ys, sub["naive_lift"], sub["adj_lift"]):
    ax.text(n + 0.15, y + h / 2, f"{n:.1f}", va="center", fontsize=8)
    ax.text(a + 0.15, y - h / 2, f"{a:.1f}", va="center", fontsize=8)
ax.axvline(1, color="black", lw=0.8, ls="--")
ax.set_yticks(ys)
ax.set_yticklabels(sub["label"], fontsize=8)
ax.set_xlabel("Lift (1.0 = no association beyond chance)")
ax.set_title("Adjusting for basket size removes most of the apparent lift for staple pairs")
ax.legend(loc="lower right")
fig.tight_layout()
fig.savefig("images/03_lift_naive_vs_adjusted.png")
plt.close(fig)

# ---------------------------------------------------------------- 4. Opportunity ranking
opp = pairs[pairs["adj_lift"] >= 1.5].copy()
opp["excess"] = opp["pair_baskets"] - opp["expected_adj"]
opp = opp.sort_values("excess", ascending=False).head(10).iloc[::-1]
labels = opp["cat_a"].str.title().str.replace("Hbc","HBC").str.replace(" Mw"," MW") + " + " + opp["cat_b"].str.title().str.replace("Hbc","HBC").str.replace(" Mw"," MW")

fig, ax = plt.subplots(figsize=(11, 5))
ax.barh(labels, opp["excess"], color="#1b6ca8")
for y, (ex, lf) in enumerate(zip(opp["excess"], opp["adj_lift"])):
    ax.text(ex + 40, y, f"lift {lf:.1f}", va="center", fontsize=8)
ax.set_xlabel("Excess baskets (observed minus expected after basket-size adjustment)")
ax.set_title("Largest cross-sell opportunities by volume (adjusted lift of 1.5 or more)")
ax.set_xlim(0, opp["excess"].max() * 1.15)
ax.tick_params(axis="y", labelsize=8)
fig.tight_layout()
fig.savefig("images/04_top_opportunities.png")
plt.close(fig)

print("Saved 4 charts to images/")
