# Post 4: Taking apart the productivity-pay gap

Source files for [Most of the productivity-pay gap is a unit conversion](index.qmd),
published 6 October 2026. Six FRED series are used to split the familiar decoupling chart
into three pieces: the price index used to deflate pay, the definition of a paycheck, and
labor's share of output.

## Files

```
post4/
├── index.qmd                         the post
├── R/
│   ├── 01_acquire.R                  pull six FRED series
│   └── 02_clean.R                    index to 1973 Q1, compute the three wedges
├── data/
│   ├── raw/
│   │   ├── fred_observations.csv     all six series, long format, quarterly
│   │   └── metadata.csv              titles, units, vintages, access time
│   └── derived/
│       └── decomposition.csv         250 quarters: four indices and three wedges
└── README.md
```

## Setup

The acquisition script needs a free FRED API key from
<https://fred.stlouisfed.org/docs/api/api_key.html>. Run `usethis::edit_r_environ()`, add
`FRED_API_KEY=your_key_here`, save, restart R. The key lives only in `~/.Renviron` and is
read with `Sys.getenv()`.

## Reproducing

From the project root, in order:

```bash
Rscript blog/posts/post4/R/01_acquire.R
Rscript blog/posts/post4/R/02_clean.R
quarto render blog/posts/post4/index.qmd
```

Only `01_acquire.R` touches the network. Needs `here`, `fredr`, `dplyr`, `tidyr`, `purrr`,
`readr`, `ggplot2` and `scales`.

## Series

| FRED id | Role |
|---|---|
| `OPHNFB` | nonfarm business labor productivity, real output per hour |
| `COMPNFB` | nonfarm business hourly compensation, nominal |
| `IPDNBS` | nonfarm business value-added output price deflator |
| `COMPRNFB` | nonfarm business real hourly compensation, CPI-deflated |
| `CPIAUCSL` | consumer price index, all urban consumers, all items |
| `AHETPI` | average hourly earnings, production and nonsupervisory workers |

`CPIAUCSL` and `AHETPI` are monthly; FRED aggregates them to quarterly averages
server-side via `frequency = "q"`, so the aggregation rule is part of the request rather
than something improvised during cleaning. The panel runs 1964 Q1 to 2026 Q2, limited at
the start by `AHETPI`.

## Construction

Four measures of pay or output per hour, each indexed to 1973 Q1 = 100:

| Index | Built as | Differs by |
|---|---|---|
| `productivity` | `OPHNFB` | the benchmark |
| `comp_output` | `COMPNFB / IPDNBS` | compensation, output prices |
| `comp_consumer` | `COMPRNFB` | compensation, consumer prices |
| `wage_consumer` | `AHETPI / CPIAUCSL` | production wage, consumer prices |

The gap in the headline chart is `productivity - wage_consumer`. It splits into three
differences between adjacent rungs, which sum to the total by construction:

- deflator, `comp_output - comp_consumer`: same pay measure, different price index
- pay concept, `comp_consumer - wage_consumer`: same price index, different paycheck
- labor share, `productivity - comp_output`: what survives both corrections

As of 2026 Q2 the total gap is 156 index points, split 36 percent deflator, 38 percent pay
concept, 27 percent labor share.

## Validation

`02_clean.R` stops unless the three wedges sum to the total gap to within 1e-9, all four
indices equal exactly 100 in the base quarter, and no quarter in the panel is missing a
value. `01_acquire.R` checks that FRED returned all six series before writing anything.

## Reading the pay-concept wedge

That wedge mixes two different things. Compensation includes employer-paid benefits that
`AHETPI` excludes, which is a measurement difference. It also covers supervisory and
managerial workers that `AHETPI` excludes, so pay growth concentrated above that line shows
up here too, which is a distributional change rather than a measurement artifact. These
series cannot separate the two, and the post says so rather than claiming the whole wedge is
bookkeeping.

## Data

FRED, Federal Reserve Bank of St. Louis. Underlying series are from the Bureau of Labor
Statistics (productivity, compensation, CPI, average hourly earnings). Accessed 6 October
2026; `metadata.csv` records the vintage of each series at download time, which matters
because productivity and compensation are revised.
