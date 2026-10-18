# Post 5: Students on Philadelphia's poverty map

Source files for [How much of Philadelphia's campus poverty is students?](index.qmd),
published 18 October 2026. Census tract poverty rates for Philadelphia are split into
college students and everyone else, to see how much of the poverty measured around Penn,
Drexel and Temple is students and how poor those neighborhoods are without them.

## Files

```
post5/
├── index.qmd                       the post
├── R/
│   ├── 01_acquire.R                ACS estimates and tract boundaries
│   └── 02_clean.R                  rates, campus flags, pooled comparisons
├── data/
│   ├── raw/
│   │   ├── acs_tracts_2024.csv     ACS estimates and margins of error, 408 tracts
│   │   ├── phl_tracts_2024.gpkg    tract boundaries (GeoPackage)
│   │   └── metadata.csv            sources, vintages, variables, access time
│   └── derived/
│       ├── phl_tracts.gpkg         boundaries joined to every derived variable
│       ├── phl_tracts.csv          the same without geometry
│       └── pooled_rates.csv        poverty rates for each campus area and the rest of the city
└── README.md
```

Everything is public Census Bureau data and small, so raw files are committed.

## Setup

The acquisition script needs a free Census API key from
<https://api.census.gov/data/key_signup.html>. The key has to be activated from the link in
the confirmation email. Run `usethis::edit_r_environ()`, add
`CENSUS_API_KEY=your_key_here`, save, restart R.

`tidycensus` 1.8.1 does not read the key from the environment by itself, and the 2024
endpoint rejects requests without one, so `01_acquire.R` passes
`key = Sys.getenv("CENSUS_API_KEY")` explicitly.

## Reproducing

From the project root, in order:

```bash
Rscript blog/posts/post5/R/01_acquire.R
Rscript blog/posts/post5/R/02_clean.R
quarto render blog/posts/post5/index.qmd
```

Only `01_acquire.R` touches the network. Needs `here`, `tidycensus`, `tigris`, `sf`,
`dplyr`, `readr`, `ggplot2` and `scales`.

## Data

American Community Survey 2020-2024 5-year estimates, census tract level, Philadelphia
County. Tracts are too small for the 1-year ACS.

| Variable | ACS id | Use |
|---|---|---|
| total population | `B01003_001` | context |
| median household income | `B19013_001` | context |
| population 3+ with poverty status determined | `B14006_001` | poverty universe |
| below poverty | `B14006_002` | poverty numerator |
| below poverty, undergraduate / graduate | `B14006_009`, `_010` | students in poverty |
| at or above poverty, undergraduate / graduate | `B14006_019`, `_020` | students not in poverty |

Boundaries are TIGER/Line cartographic boundary files (`cb = TRUE`), which are clipped to
the shoreline so rivers are not drawn as tract area.

## Construction

Both poverty rates come from table B14006, so they share one universe and differ only in
whether college and graduate students are counted:

- `pov_all = below / universe`
- `pov_noncol = (below - students below) / (universe - students)`

Poverty status is not determined for people living in dormitories, so these rates, and
`student_share`, cover off-campus students only. Those are the only students who can move
a tract's poverty rate.

A rate is set to missing when its denominator is under 500 people. A campus tract is one
whose centroid is within 1 km of Penn, Drexel or Temple and where off-campus students are
at least 25 percent of the poverty universe. That gives five tracts in University City and
three around Temple. Distances are computed in UTM zone 18N (EPSG:32618), in metres; doing
it in latitude and longitude would measure angles, not distance.

Pooled rates in `pooled_rates.csv` are computed from summed counts, not by averaging tract
rates.

## Validation

`02_clean.R` stops unless the student and non-student counts add back exactly to the
totals, every rate lies between 0 and 1, and the campus flag finds tracts at both campuses.
`01_acquire.R` checks that the boundary file and the ACS table cover the same number of
tracts.

## Limitations

Tract estimates have wide margins of error; the raw file keeps every margin (`...M`
columns) for anyone who wants to test whether a given difference is distinguishable from
noise. Five-year pooling blends 2020 through 2024, including the pandemic. The 1 km radius
and 25 percent threshold are judgment calls.
