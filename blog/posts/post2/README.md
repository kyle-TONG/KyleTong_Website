# Post 2: What NBA production costs

Source files for [Paying for wins](index.qmd), published 21 September 2026. Two
Basketball-Reference pages are scraped with `rvest` to price 2026-27 salaries against
2025-26 production, and the cost of a point of VORP is compared across salary bands.

## Files

```
post2/
├── index.qmd                        the post
├── R/
│   ├── 01_acquire.R                 fetch the two pages, save HTML snapshots
│   └── 02_clean.R                   parse, join production to salary
├── data/
│   ├── raw/
│   │   ├── bbref_advanced_2026.html      snapshot, 2025-26 advanced stats
│   │   ├── bbref_contracts_players.html  snapshot, contracts from 2026-27
│   │   └── metadata.csv                  URLs, access times, file sizes
│   └── derived/
│       ├── analysis_data.csv             348 players, the analysis sample
│       └── unmatched_contracts.csv       contracts with no 2025-26 season
└── README.md
```

## Reproducing

From the project root, in order:

```bash
Rscript blog/posts/post2/R/01_acquire.R
Rscript blog/posts/post2/R/02_clean.R
quarto render blog/posts/post2/index.qmd
```

Only `01_acquire.R` touches the network, and it reads the cached snapshots unless called
with `--force`. Needs `here`, `rvest`, `httr`, `dplyr`, `stringr`, `readr`, `stringi`, `ggplot2`,
`scales` and `knitr`.

## Data and collection

Both pages come from basketball-reference.com:

- `/leagues/NBA_2026_advanced.html`, per-player advanced statistics for 2025-26
- `/contracts/players.html`, salary by season from 2026-27 onward

Their `robots.txt` allows `/leagues/` and `/contracts/` for a generic user agent, blocks
`*/gamelog/`, `*/splits/`, `*/on-off/`, `*/lineups/` and `*/shooting/`, which this project
does not request, and asks for `Crawl-delay: 3`. The acquisition script waits four seconds
between requests, sends an identifying user agent, and makes two requests in total.
Snapshots are cached so that re-running the parse costs no further requests.

Statistics are copyright Sports Reference LLC. The derived files here are summary measures
built for a class exercise, not a redistribution of their tables.

## Cleaning notes

Player names carry bracketed footnote markers, which are stripped before the join. A player
traded mid-season appears once per team plus a combined `2TM` row sharing the same rank;
the combined row is kept. The contracts table has a two-row header, so `html_table()`
returns the real column names as the first row of data. Salaries arrive as strings like
`$62,587,158` and go through `parse_number()`.

The join is on the player name after transliterating accents, dropping punctuation and
removing generational suffixes. It matched 416 of 484 contracts. The misses are 2026 draft
picks and players who missed the 2025-26 season, listed in `unmatched_contracts.csv`.

## Validation

`02_clean.R` recomputes VORP from the scraped BPM and minutes columns, using the identity
`VORP = (BPM + 2) * MP / (48 * 82)`, and stops if any player disagrees by more than 0.15.
That catches columns read in the wrong order and numbers parsed as text. It also checks
that the salary column parsed to positive numbers and that the match rate clears 75 percent.
