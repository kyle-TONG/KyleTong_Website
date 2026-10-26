"""Download Penn World Table 11.0 and the Our World in Data country-to-continent
map, and record where they came from.

    python blog/posts/post7/py/01_acquire.py

Both files are cached in data/raw/; delete them to force a fresh download.
PWT 11.0 is licensed CC BY 4.0 and the OWID file CC BY, so both can be kept in
the repository with attribution.
"""

import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

POST = Path(__file__).resolve().parents[1]
RAW = POST / "data" / "raw"
RAW.mkdir(parents=True, exist_ok=True)

SOURCES = [
    {
        "file": "pwt110.dta",
        "source": "Penn World Table 11.0, Groningen Growth and Development Centre",
        "url": "https://dataverse.nl/api/access/datafile/554030",
        "doi": "10.34894/FABVLR",
        "license": "CC BY 4.0",
    },
    {
        "file": "owid_continents.csv",
        "source": "Our World in Data, continents according to Our World in Data",
        "url": ("https://ourworldindata.org/grapher/"
                "continents-according-to-our-world-in-data.csv"
                "?v=1&csvType=full&useColumnShortNames=true"),
        "doi": "",
        "license": "CC BY 4.0",
    },
]

for src in SOURCES:
    path = RAW / src["file"]
    if path.exists():
        print(f"cached   {src['file']}")
        continue
    print(f"fetching {src['url']}")
    req = urllib.request.Request(src["url"], headers={"User-Agent": "KyleTong-coursework/1.0"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        path.write_bytes(resp.read())

# Validate before anything downstream relies on the files.
pwt = pd.read_stata(RAW / "pwt110.dta")
assert {"countrycode", "year", "rgdpe", "rgdpna", "pop"} <= set(pwt.columns)
assert pwt["year"].min() <= 1960 and pwt["year"].max() >= 2023

continents = pd.read_csv(RAW / "owid_continents.csv")
assert {"code", "owid_region"} <= set(continents.columns)
missing = set(pwt["countrycode"]) - set(continents["code"])
assert not missing, f"PWT countries without a continent: {sorted(missing)}"

meta = pd.DataFrame(SOURCES).assign(
    bytes=[(RAW / s["file"]).stat().st_size for s in SOURCES],
    accessed_at=[datetime.fromtimestamp((RAW / s["file"]).stat().st_mtime, timezone.utc)
                 .strftime("%Y-%m-%d %H:%M:%S UTC") for s in SOURCES],
)
meta.to_csv(RAW / "metadata.csv", index=False)

print(f"PWT: {pwt['countrycode'].nunique()} countries, "
      f"{pwt['year'].min()}-{pwt['year'].max()}; all matched to a continent")
