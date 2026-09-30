# Post 3: Participation and the age structure

Source files for [Participation fell, nobody stopped working](index.qmd), published
28 September 2026. IPUMS CPS microdata is used to split the decline in US labor-force
participation since 1990 into what people did and how the population aged.

## Files

```
post3/
├── index.qmd                     the post
├── R/
│   ├── 01_acquire.R              define, submit and download the IPUMS extract
│   └── 02_clean.R                collapse microdata to weighted rates by age
├── data/
│   ├── raw/
│   │   ├── cps_00001.dat.gz      microdata, NOT in the repository
│   │   ├── cps_00001.xml         DDI codebook, NOT in the repository
│   │   └── metadata.csv          samples, variables, access time
│   └── derived/
│       ├── lfp_by_age.csv        148 rows: year x age group
│       └── weighting_gap.csv     weighted vs unweighted rate, by year
└── README.md
```

The extract is 72 MB and IPUMS asks users to register before downloading, so
`data/raw/*.dat.gz` and `data/raw/*.xml` are listed in the project `.gitignore` and only
the aggregated tables are committed. Anyone with an IPUMS account regenerates the raw files
by running `01_acquire.R`. The license itself allows redistribution provided no fee is
charged; size and provenance are the reasons the files are absent, not a prohibition.

## Setup

The extract is built through the IPUMS API, which needs a free account and a key:

1. Register at <https://cps.ipums.org/cps/>.
2. Create a key at <https://account.ipums.org/api_keys>.
3. Run `usethis::edit_r_environ()` in R, add `IPUMS_API_KEY=your_key_here`, save, restart R.

The key lives only in `~/.Renviron`. Scripts read it with `Sys.getenv()` and never write it
to disk or to the repository.

## Reproducing

From the project root, in order:

```bash
Rscript blog/posts/post3/R/01_acquire.R
Rscript blog/posts/post3/R/02_clean.R
quarto render blog/posts/post3/index.qmd
```

`01_acquire.R` submits the extract and waits while IPUMS builds it, which takes several
minutes, then downloads about 72 MB. It skips the download if an extract is already in
`data/raw/`. Needs `here`, `ipumsr`, `dplyr`, `readr`, `tidyr`, `ggplot2` and `scales`.

## Data

IPUMS CPS, every March Basic Monthly sample from 1990 to 2026: 37 samples, 3,616,192 person
records. Variables are AGE, SEX, LABFORCE, EMPSTAT and WTFINL.

Basic Monthly samples have ids like `cps2026_03b`. The ASEC supplement uses an `s` suffix
and a different weight, so `01_acquire.R` matches the pattern against the live sample
metadata rather than hard-coding a list.

The license requires this citation, which is reproduced from the DDI that came with the
extract:

> Sarah Flood, Miriam King, Renae Rodgers, Steven Ruggles, J. Robert Warren, Daniel
> Backman, Etienne Breton, Grace Cooper, Julia A. Rivera Drew, Stephanie Richards, David
> Van Riper, and Kari C.W. Williams. IPUMS CPS: Version 13.0 [dataset]. Minneapolis, MN:
> IPUMS, 2025. <https://doi.org/10.18128/D030.V13.0>

## Weights

WTFINL, the final person-level weight for the Basic Monthly CPS. It is the right weight
here because the samples are Basic Monthly: ASECWT applies only to ASEC samples, EARNWT to
earnings variables from the outgoing rotation groups, and HWTFINL to household-level
statistics.

Every statistic in the post is weighted. Participation rates use
`weighted.mean(in_lf, wtfinl)`, population counts use `sum(wtfinl)`, and age shares divide
one by the other. The shift-share decomposition is built from those weighted shares and
rates, so nothing downstream is unweighted. The `n` column in `lfp_by_age.csv` is the
unweighted record count, kept for documentation and used in no calculation.

Estimates are computed within each year before anything is compared across years. Pooling
by summing WTFINL across months would treat several overlapping cross-sections as one
population, which it is not.

The weights matter, increasingly. In March 2026 the unweighted participation rate is 59.3
percent against a weighted 62.1, because people over 65 are 28.9 percent of the interviewed
sample and 23.4 percent of the population.

Weights give unbiased point estimates but not correct standard errors, since the CPS is a
complex survey rather than a simple random sample. Replicate weights were not requested,
so the post reports no standard errors and no significance tests.

## Validation

`02_clean.R` stops unless three things hold. The weighted group rates, recombined with
their population shares, reproduce the overall participation rate to within 1e-9. The
weighted population totals fall between 150 and 350 million, which catches a failure to
restore the implied decimals in WTFINL; the actual totals run from 188.6 million in 1990 to
274.9 million in 2026, matching the published 16-and-over civilian noninstitutional
population. And the extract contains more than a million usable person records.
