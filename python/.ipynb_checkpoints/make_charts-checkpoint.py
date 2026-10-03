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
colors = ["#d95f02" if s == "yes" else "#6b6b6b" for s in
cd /Users/sanjib700/Desktop/My_Projects/SQL-retail-basket-analysis
mkdir -p results
mv basket_adjusted_output.txt results/ 2>/dev/null

cat > sql/10_export_and_priorities.sql << 'EOF'
-- 10_export_and_priorities.sql
-- 1) Exports result tables to CSV (for charts), 2) ranks cross-sell opportunities by
-- excess baskets (observed - expected) so volume matters, not just ratio.
-- Run from the project root so the relative paths work.

\copy (SELECT c.month_start, COUNT(DISTINCT t.day) AS days_in_data, COUNT(*) AS baskets, COUNT(DISTINCT t.household_key) AS active_households, ROUND(SUM(t.basket_value)) AS revenue FROM retail.transactions t JOIN retail.calendar c USING (day) GROUP BY c.month_start ORDER BY c.month_start) TO 'results/monthly_revenue.csv' CSV HEADER

\copy (SELECT cohort_month, cohort_size, month_number, active_households, retention_pct FROM retail.cohort_retention ORDER BY cohort_month, month_number) TO 'results/cohort_retention.csv' CSV HEADER

\copy (SELECT * FROM retail.cohort_category_results ORDER BY uplift_pct DESC) TO 'results/cohort_category_results.csv' CSV HEADER

\copy (SELECT p.cat_a, p.cat_b, a.dept_a, a.dept_b, p.pair_baskets, p.support, p.confidence_a_to_b, p.confidence_b_to_a, a.naive_lift, a.expected_adj, a.adj_lift FROM retail.category_pairs p JOIN retail.category_pairs_adjusted a USING (cat_a, cat_b) WHERE p.pair_baskets >= 300 ORDER BY a.adj_lift DESC) TO 'results/category_pairs_adjusted.csv' CSV HEADER

\copy (SELECT * FROM retail.cleaning_log ORDER BY step) TO 'results/cleaning_log.csv' CSV HEADER

SET search_path = retail;

-- Opportunity ranking: pairs with real affinity (adjusted lift >= 1.5), by excess baskets
SELECT cat_a, cat_b, dept_a, dept_b, pair_baskets, expected_adj,
       pair_baskets - expected_adj AS excess_baskets,
       adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300 AND adj_lift >= 1.5
ORDER BY excess_baskets DESC
LIMIT 15;

-- Same ranking restricted to different departments
SELECT cat_a, cat_b, dept_a, dept_b, pair_baskets, expected_adj,
       pair_baskets - expected_adj AS excess_baskets,
       adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300 AND adj_lift >= 1.5 AND dept_a IS DISTINCT FROM dept_b
ORDER BY excess_baskets DESC
LIMIT 10;

-- Biggest substitute pairs by volume: baskets "missing" versus expectation
SELECT cat_a, cat_b, pair_baskets, expected_adj,
       expected_adj - pair_baskets AS missing_baskets,
       adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300 AND adj_lift <= 0.7
ORDER BY missing_baskets DESC
LIMIT 10;
