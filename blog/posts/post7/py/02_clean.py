"""Turn PWT 11.0 into decade-by-decade growth rates and convergence slopes.

    python blog/posts/post7/py/02_clean.py

Reads data/raw/, writes data/derived/decade_growth.csv (one row per country
and decade) and data/derived/convergence_slopes.csv (one row per decade).
"""

from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

POST = Path(__file__).resolve().parents[1]
RAW = POST / "data" / "raw"
DERIVED = POST / "data" / "derived"
DERIVED.mkdir(parents=True, exist_ok=True)

# The 2010s window stops in 2019 so that the pandemic collapse of 2020 does not
# decide the last decade's result. Growth is annualized, so a nine-year window
# is comparable with the ten-year ones.
WINDOWS = {"1960s": (1960, 1970), "1970s": (1970, 1980), "1980s": (1980, 1990),
           "1990s": (1990, 2000), "2000s": (2000, 2010), "2010s": (2010, 2019)}
MIN_POP = 1.0  # millions; keeps micro-states from dominating an unweighted fit

pwt = pd.read_stata(RAW / "pwt110.dta")[["countrycode", "country", "year",
                                        "rgdpe", "rgdpna", "pop"]]
continents = (pd.read_csv(RAW / "owid_continents.csv")
                .rename(columns={"code": "countrycode", "owid_region": "continent"})
                [["countrycode", "continent"]])

# Two GDP measures, used for what each is designed for (PWT user guide):
#   rgdpe  expenditure-side GDP at chained PPPs, comparable ACROSS countries -> income level
#   rgdpna national-accounts GDP at constant prices, comparable OVER TIME -> growth
pwt = pwt.dropna(subset=["rgdpe", "rgdpna", "pop"])
pwt["level_pc"] = pwt["rgdpe"] / pwt["pop"]   # mil. $ / mil. people = $ per person
pwt["na_pc"] = pwt["rgdpna"] / pwt["pop"]

rows = []
for decade, (start, end) in WINDOWS.items():
    a = pwt[pwt["year"] == start].set_index("countrycode")
    b = pwt[pwt["year"] == end].set_index("countrycode")
    j = a.join(b[["na_pc"]], rsuffix="_end", how="inner")
    j = j[j["pop"] >= MIN_POP]
    j["growth"] = 100 * (np.log(j["na_pc_end"]) - np.log(j["na_pc"])) / (end - start)
    rows.append(j.reset_index().assign(decade=decade, start=start, end=end))

growth = (pd.concat(rows, ignore_index=True)
            .merge(continents, on="countrycode", how="left")
            [["decade", "start", "end", "countrycode", "country", "continent",
              "level_pc", "pop", "growth"]]
            .rename(columns={"level_pc": "gdp_pc_start", "pop": "pop_start"}))

assert growth["continent"].notna().all()
assert growth["growth"].between(-20, 25).all()
assert not growth.duplicated(["decade", "countrycode"]).any()

# Convergence slope: annual growth on log initial income. Negative means poorer
# countries grew faster. Unweighted treats every country as one observation;
# weighting by population treats every person as one.
slopes = []
for decade, g in growth.groupby("decade", sort=False):
    g = g.assign(log_y=np.log(g["gdp_pc_start"]))
    ols = smf.ols("growth ~ log_y", g).fit()
    wls = smf.wls("growth ~ log_y", g, weights=g["pop_start"]).fit()
    slopes.append({"decade": decade, "countries": len(g),
                   "slope": ols.params["log_y"], "se": ols.bse["log_y"],
                   "slope_pop": wls.params["log_y"], "se_pop": wls.bse["log_y"]})
slopes = pd.DataFrame(slopes)

growth.to_csv(DERIVED / "decade_growth.csv", index=False)
slopes.to_csv(DERIVED / "convergence_slopes.csv", index=False)
print(slopes.round(3).to_string(index=False))
