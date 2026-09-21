---
title: "Data notes: Basketball-Reference salary and production scrape"
subtitle: "Provenance, cleaning decisions and known limitations"
author: "Kyle Tong"
date: 2026-09-21
---

These notes accompany [Paying for wins](../index.qmd). They record where the data came
from, what was done to it, and what it cannot support.

## Sources

Three pages from Basketball-Reference, fetched once and cached as HTML snapshots in
`data/raw/`:

| Key | Page | What it gives |
|---|---|---|
| `advanced_2026` | `/leagues/NBA_2026_advanced.html` | 2025-26 advanced stats: minutes, PER, USG%, WS, WS/48, BPM, VORP |
| `advanced_2025` | `/leagues/NBA_2025_advanced.html` | the same for 2024-25, used to stabilise one-season BPM |
| `contracts` | `/contracts/players.html` | salary by season from 2026-27 through 2031-32, plus guaranteed money |

Exact URLs, file sizes and access timestamps are in `data/raw/metadata.csv`, written by
`R/01_acquire.R` at download time.

Basketball-Reference has no public API for these tables and no bulk download of them, so
scraping is the remaining structured option. `robots.txt` permits `/leagues/` and
`/contracts/` for a generic user agent, disallows `*/gamelog/`, `*/splits/`,
`*/on-off/`, `*/lineups/` and `*/shooting/`, none of which are touched here, and asks for
`Crawl-delay: 3`. The acquisition script waits four seconds between requests, sends an
identifying user agent with a contact address, and makes three requests in total. Re-runs
read the cached snapshots unless called with `--force`.

Basketball-Reference data are copyright Sports Reference LLC. Nothing here redistributes
the underlying tables; the derived files are summary measures built for a class exercise.

## Pipeline

```
R/00_config.R    paths, source list, constants, text helpers
R/01_acquire.R   fetch -> data/raw/*.html + metadata.csv
R/02_clean.R     parse -> data/derived/*.csv
R/03_analyze.R   price -> results/tables/*.csv
index.qmd        narrative, figures, tables
```

Each script is runnable on its own with `Rscript`, in order. Only `01_acquire.R` touches
the network.

## Cleaning decisions

Footnote markers. Names on Basketball-Reference carry bracketed footnotes and, on some
pages, asterisks for Hall of Fame members. `clean_text()` strips `[...]` and `*` before
anything else looks at the string.

Traded players. A player who changed teams mid-season appears once per team plus a
combined `2TM` or `3TM` row, all sharing a rank. The combined row is kept and the partial
rows dropped, so each player contributes one season.

Name matching. The stats pages and the contracts page are joined on the player name after
transliterating accents (Jokić becomes Jokic), dropping periods and apostrophes,
converting hyphens to spaces, removing generational suffixes, and lower-casing. 416 of
484 contracts matched a 2025-26 season, or 86 percent. The unmatched contracts are
written to `data/derived/unmatched_contracts.csv`; they are overwhelmingly 2026 draft
picks with no NBA minutes yet and players who missed all of last season, not name
collisions.

Minutes floor. The analysis sample keeps players with at least 500 minutes in 2025-26.
Below that, rate statistics are too noisy to price.

Duplicate contracts. If a name appears more than once on the contracts page, the larger
2026-27 figure is kept.

## Validation

VORP on Basketball-Reference satisfies

$$\text{VORP} = (\text{BPM} + 2) \times \frac{\text{MP}}{48 \times 82},$$

so `02_clean.R` recomputes it from the parsed BPM and minutes columns and stops if any
player's recomputed value differs from the scraped value by more than 0.15. This catches
the common scraping failures at once: columns shifted by one, numbers parsed as text,
header rows read as data. The script also checks that each snapshot contains the table it
was fetched for, that the salary column parsed to positive numbers, that no player-season
is duplicated, and that the match rate clears 75 percent.

## Limitations

The production measure and the salary refer to different seasons. Salary is the 2026-27
figure; production is 2025-26, blended with 2024-25 at one-third weight. Players change
between June and October, and a projection built this way will be wrong about the ones
who change most.

BPM and VORP are box-score estimates. They do not see defensive positioning, screening,
gravity, or anything else that does not end in a counted event, and their positional
adjustments are contested. The position comparison in the post is the finding most
exposed to this.

Players with no 2025-26 minutes are absent from the analysis, which removes the largest
contracts belonging to injured stars. Any statement about the efficiency of the top of the
market is conditional on having played.

Salary is not the full cost of a roster spot. Luxury tax, apron restrictions, trade
exceptions and the value of draft picks all change what a contract is worth to a team, and
none of them are in this data.

## Reuse

```bash
Rscript blog/posts/post2/R/01_acquire.R   # cached; add --force to re-download
Rscript blog/posts/post2/R/02_clean.R
Rscript blog/posts/post2/R/03_analyze.R
```
