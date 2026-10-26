# Post 7: Are poor countries catching up?

Source files for [Are poor countries catching up?](index.qmd), published 26 October 2026.
An interactive Plotly chart of cross-country growth by decade, 1960 to 2019, built from
Penn World Table 11.0: a bubble scatter of starting income against growth with a decade
slider, and a chart of the convergence slope by decade, unweighted and weighted by
population.

## Files

```
post7/
├── index.qmd                       the post (Python, Jupyter engine, Plotly)
├── py/
│   ├── 01_acquire.py               download PWT 11.0 and the continent map
│   └── 02_clean.py                 decade growth rates and convergence slopes
├── data/
│   ├── raw/
│   │   ├── pwt110.dta              Penn World Table 11.0
│   │   ├── owid_continents.csv     country-to-continent map, Our World in Data
│   │   └── metadata.csv            URLs, DOI, licenses, access time
│   └── derived/
│       ├── decade_growth.csv       one row per country and decade
│       └── convergence_slopes.csv  one row per decade
└── README.md
```

Both sources are licensed CC BY 4.0, so the raw files are committed with attribution.

## Reproducing

From the project root:

```bash
python blog/posts/post7/py/01_acquire.py
python blog/posts/post7/py/02_clean.py
quarto render blog/posts/post7/index.qmd
```

`01_acquire.py` downloads only if a file is missing from `data/raw/`. Needs `pandas`,
`numpy`, `statsmodels` and `plotly`. Like post 6, the post asks for the Jupyter kernel
`anaconda3`; see post 6's README.

## Construction

For each decade (1960-1970, ..., 2000-2010, and 2010-2019 to leave out the 2020 pandemic
collapse), every country in PWT with data at both ends and at least one million people at
the start.

| Variable | Built from | Why |
|---|---|---|
| income at start | `rgdpe / pop` | expenditure-side GDP at chained PPPs, 2021 dollars: PWT's measure for comparing living standards across countries |
| annual growth | log change in `rgdpna / pop`, divided by years | national-accounts GDP at constant prices: PWT's measure for growth over time |

Using different series for the two axes also keeps measurement error in the PPP level from
appearing on both sides of the regression, which would manufacture a negative slope.

The convergence slope is the OLS coefficient of annual growth (percent) on log starting
income. It is estimated twice per decade: unweighted, so each country is one observation,
and weighted by starting population, so each person counts once.

Continents follow Our World in Data's classification; all 185 PWT economies match.

## Validation

`01_acquire.py` checks that PWT has the needed columns and years and that every PWT country
has a continent. `02_clean.py` checks that every row has a continent, that no growth rate is
implausible (outside -20 to 25 percent a year), and that country-decade pairs are unique.

## Sources

Feenstra, Robert C., Robert Inklaar, and Marcel P. Timmer. 2015. "The Next Generation of
the Penn World Table." *American Economic Review* 105 (10): 3150-3182. PWT 11.0,
doi:10.34894/FABVLR.

Our World in Data, "Continents according to Our World in Data,"
<https://ourworldindata.org/grapher/continents-according-to-our-world-in-data>.

Patel, Dev, Justin Sandefur, and Arvind Subramanian. 2021. "The New Era of Unconditional
Convergence." *Journal of Development Economics* 152: 102687.
