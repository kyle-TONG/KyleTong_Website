# 02_clean.R -------------------------------------------------------------
# Read the IPUMS CPS extract and collapse it to weighted labor-force
# participation and population shares by year and age group. Reads only from
# data/raw/, writes one small table to data/derived/.

suppressPackageStartupMessages({
  library(here)
  library(ipumsr)
  library(dplyr)
  library(readr)
})

POST_DIR    <- here("blog", "posts", "post3")
RAW_DIR     <- file.path(POST_DIR, "data", "raw")
DERIVED_DIR <- file.path(POST_DIR, "data", "derived")
dir.create(DERIVED_DIR, recursive = TRUE, showWarnings = FALSE)

ddi_file <- list.files(RAW_DIR, pattern = "\\.xml$", full.names = TRUE)
stopifnot(length(ddi_file) == 1)

ddi <- read_ipums_ddi(ddi_file)
cps <- read_ipums_micro(ddi, verbose = FALSE)

names(cps) <- tolower(names(cps))

# Universe: civilians 16 and over for whom labor-force status is defined.
# LABFORCE is 0 for not-in-universe, 1 for not in the labor force, 2 for in
# it, so dropping 0 is what defines the population the rates describe.
adults <- cps |>
  filter(age >= 16, labforce %in% c(1, 2), wtfinl > 0) |>
  mutate(
    in_lf     = as.integer(labforce == 2),
    age_group = cut(age, breaks = c(15, 24, 54, 64, Inf),
                    labels = c("16-24", "25-54", "55-64", "65+"))
  )

stopifnot(nrow(adults) > 1e6, !any(is.na(adults$age_group)))

# Every number below is weighted by WTFINL. An unweighted mean would describe
# the people CPS happened to interview, not the population they stand for.
by_group <- adults |>
  group_by(year, age_group) |>
  summarise(lfp        = weighted.mean(in_lf, wtfinl),
            population = sum(wtfinl),
            n          = n(),
            .groups    = "drop") |>
  group_by(year) |>
  mutate(share = population / sum(population)) |>
  ungroup()

overall <- adults |>
  group_by(year) |>
  summarise(lfp_all = weighted.mean(in_lf, wtfinl), .groups = "drop")

# The weighted average of the group rates has to reproduce the overall rate.
check <- by_group |>
  group_by(year) |>
  summarise(lfp_rebuilt = sum(share * lfp), .groups = "drop") |>
  left_join(overall, by = "year")

stopifnot(max(abs(check$lfp_rebuilt - check$lfp_all)) < 1e-9)

# WTFINL carries implied decimals in the fixed-width file, which ipumsr
# restores from the DDI. If that went wrong the weights would be off by orders
# of magnitude, so check that they still sum to a plausible 16+ civilian
# noninstitutional population (188.6 million in 1990, 274.9 million in 2026).
pop_totals <- by_group |>
  group_by(year) |>
  summarise(pop = sum(population), .groups = "drop")

stopifnot(all(pop_totals$pop > 150e6), all(pop_totals$pop < 350e6))

# How much the weights matter, for the record.
weighting_gap <- adults |>
  group_by(year) |>
  summarise(weighted   = weighted.mean(in_lf, wtfinl),
            unweighted = mean(in_lf),
            n          = n(),
            .groups    = "drop") |>
  mutate(gap = weighted - unweighted)

write_csv(weighting_gap, file.path(DERIVED_DIR, "weighting_gap.csv"))

write_csv(by_group, file.path(DERIVED_DIR, "lfp_by_age.csv"))

message(sprintf("wrote %d rows, %d to %d, from %s person records",
                nrow(by_group), min(by_group$year), max(by_group$year),
                format(nrow(adults), big.mark = ",")))
