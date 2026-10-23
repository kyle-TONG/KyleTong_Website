# Post 6: Matching parents and children in the PSID with SQL

Source files for [Matching parents and children in the PSID with SQL](index.qmd), published
23 October 2026. A tutorial on real PSID data: load the individual file, the Parent
Identification File and a family-file extract into SQLite, match children to parents with
`JOIN`, build single-year and multi-year income measures with `GROUP BY`, and estimate the
intergenerational elasticity of income (IGE). It shows attenuation from single-year income
and life-cycle bias from the ages at which each generation's income is measured.

## Files

```
post6/
├── index.qmd                   the tutorial (Python, Jupyter engine)
├── py/
│   └── 01_prepare.py           reads the three PSID downloads, writes data/psid/
├── data/
│   ├── cpi_annual.csv          CPI-U annual averages, FRED CPIAUCSL
│   ├── raw/                    PSID downloads (not committed)
│   │   ├── ind2023er.zip       cross-year individual file, 1968-2023
│   │   ├── pid23.zip           Parent Identification File, 2023
│   │   └── J366546.zip         Data Center family extract
│   └── psid/                   prepared CSV files (not committed)
│       ├── individuals.csv     85,536 people: IDs, sex; interview number, sequence
│       │                       number, relation to reference person, age in 2017-2023
│       ├── family_income.csv   one row per family per wave: RP and spouse labor income
│       └── parents.csv         birth mother and birth father of each person
└── README.md
```

The PSID conditions of use do not allow redistribution, so `data/raw/` and `data/psid/` are
listed in the project `.gitignore`. Only the rendered results go online.

## Getting the data

All three downloads need a free PSID account (psidonline.isr.umich.edu).

1. The packaged cross-year individual file, 1968-2023 (`ind2023er.zip`).
2. The packaged Parent Identification File, 2023 (`pid23.zip`).
3. A Data Center extract from the family files for 2017, 2019, 2021 and 2023, with these
   variables. Download as Excel; the job number names the zip.

| Wave | Interview number | RP labor income | Spouse labor income |
|---|---|---|---|
| 2017 | ER66002 | ER71293 (2016) | ER71321 (2016) |
| 2019 | ER72002 | ER77315 (2018) | ER77343 (2018) |
| 2021 | ER78002 | ER81642 (2020) | ER81670 (2020) |
| 2023 | ER82002 | ER85496 (2022) | ER85524 (2022) |

If the Data Center job number differs from `J366546`, change the file names at the top of
section 2 in `py/01_prepare.py`.

## Reproducing

From the project root:

```bash
python blog/posts/post6/py/01_prepare.py
quarto render blog/posts/post6/index.qmd
```

`01_prepare.py` takes under 10 seconds. It reads column positions from the `.do` files
inside the zips, so it does not need the 560 MB text file unpacked. It also strips a
`<sheetPr synchVertical=...>` tag from the Data Center spreadsheet, which recent versions of
`openpyxl` refuse to read. Needs `pandas` and `openpyxl`; the tutorial also needs `numpy`,
`statsmodels` and `matplotlib`. SQLite ships with Python.

`index.qmd` asks for the Jupyter kernel named `anaconda3`. On another machine,
register a kernel with that name or change the `jupyter:` line to `python3`.

## Variables and codes used

| Individual file, per wave | 2017 | 2019 | 2021 | 2023 |
|---|---|---|---|---|
| interview number | ER34501 | ER34701 | ER34901 | ER35101 |
| sequence number | ER34502 | ER34702 | ER34902 | ER35102 |
| relation to reference person | ER34503 | ER34703 | ER34903 | ER35103 |
| age | ER34504 | ER34704 | ER34904 | ER35104 |

Person identifiers are `ER30001` (1968 interview number) and `ER30002` (person number).
Parent links are `PID2`-`PID5` (child and birth mother) and `PID23`-`PID24` (birth father).

Sequence number 1-20 means the person lived in the family at the interview. The reference
person is relation 10 with sequence number 1; a spouse is relation 20 and a cohabiting
partner relation 22. Labor income is 0 when there is no labor income or no spouse in the
family, and excludes farm income and the labor part of business income.

## Sample and results

Children are people who are the reference person or spouse in all four waves with positive
family labor income (RP plus spouse) each year; their parents' family labor income must also
be positive in all four years, averaged over mother and father when they live apart. This
gives 1,012 pairs from 546 original 1968 families. Estimates are unweighted, with standard
errors clustered on the 1968 family.

| Measure | IGE |
|---|---|
| one year, both generations (mean over the four years) | 0.10 |
| four-year average, both generations | 0.15 |
| child 2016 (about age 30) on parents' four-year average | 0.09 |
| child 2022 (about age 36) on parents' four-year average | 0.21 |
| child four-year average on parents 2016 (about age 56) | 0.13 |
| child four-year average on parents 2022 (about age 62) | 0.07 |

The levels are far below the 0.4-0.6 in the literature because parents are measured late
in their careers and children early, over a short window. Adding earlier family-file waves
to the Data Center extract would let the same SQL measure parents when their children were
growing up.

## References

Haider, Steven, and Gary Solon. 2006. "Life-Cycle Variation in the Association between
Current and Lifetime Earnings." *American Economic Review* 96 (4): 1308-1320.

Mazumder, Bhashkar. 2005. "Fortunate Sons: New Estimates of Intergenerational Mobility in
the United States Using Social Security Earnings Data." *Review of Economics and
Statistics* 87 (2): 235-255.

Solon, Gary. 1992. "Intergenerational Income Mobility in the United States." *American
Economic Review* 82 (3): 393-408.
