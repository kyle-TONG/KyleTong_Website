# 02_clean.R -------------------------------------------------------------
# Turn the FRED series into four comparable indices and split the gap between
# productivity and the production worker's real wage into three wedges.
# Reads only from data/raw/, writes one table to data/derived/.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(readr)
})

POST_DIR    <- here("blog", "posts", "post4")
RAW_DIR     <- file.path(POST_DIR, "data", "raw")
DERIVED_DIR <- file.path(POST_DIR, "data", "derived")
dir.create(DERIVED_DIR, recursive = TRUE, showWarnings = FALSE)

# 1973 Q1 is the conventional starting point for this comparison: productivity
# and pay track each other closely before it and visibly separate after.
BASE <- as.Date("1973-01-01")

panel <- read_csv(file.path(RAW_DIR, "fred_observations.csv"),
                  show_col_types = FALSE) |>
  pivot_wider(names_from = series_id, values_from = value) |>
  arrange(date)

# Four measures of the same thing, differing only in the deflator and in which
# paycheck is counted. Everything is a level in its own units until here.
levels_q <- panel |>
  filter(!is.na(OPHNFB), !is.na(AHETPI)) |>
  transmute(
    date,
    productivity  = OPHNFB,              # real output per hour
    comp_output   = COMPNFB / IPDNBS,    # compensation per hour, output prices
    comp_consumer = COMPRNFB,            # compensation per hour, consumer prices
    wage_consumer = AHETPI / CPIAUCSL    # production worker wage, consumer prices
  )

rebase <- function(x, base_value) 100 * x / base_value

base_row <- levels_q |> filter(date == BASE)
stopifnot(nrow(base_row) == 1)

indices <- levels_q |>
  mutate(across(-date, ~ rebase(.x, base_row[[cur_column()]])))

# The gap between the headline pair, split into the steps that close it. The
# three wedges are differences between adjacent rungs, so they add to the total
# by construction.
wedges <- indices |>
  mutate(
    gap_total    = productivity - wage_consumer,
    w_deflator   = comp_output   - comp_consumer,
    w_pay_concept = comp_consumer - wage_consumer,
    w_labor_share = productivity - comp_output
  )

stopifnot(max(abs(with(wedges,
  w_deflator + w_pay_concept + w_labor_share - gap_total))) < 1e-9)

# Sanity: all four indices equal 100 in the base quarter, and nothing is
# missing in the middle of the sample.
stopifnot(all(abs(unlist(base_row |>
  mutate(across(-date, ~ rebase(.x, base_row[[cur_column()]]))) |>
  select(-date)) - 100) < 1e-9))
stopifnot(!any(is.na(wedges)))

write_csv(wedges, file.path(DERIVED_DIR, "decomposition.csv"))

last <- slice_tail(wedges, n = 1)
message(sprintf("%s to %s, %d quarters", min(wedges$date), max(wedges$date),
                nrow(wedges)))
message(sprintf("productivity %.0f, wage %.0f, gap %.0f points",
                last$productivity, last$wage_consumer, last$gap_total))
message(sprintf("deflator %.0f%%, pay concept %.0f%%, labor share %.0f%%",
                100 * last$w_deflator / last$gap_total,
                100 * last$w_pay_concept / last$gap_total,
                100 * last$w_labor_share / last$gap_total))
