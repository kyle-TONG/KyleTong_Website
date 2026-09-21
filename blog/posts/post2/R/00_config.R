# 00_config.R ------------------------------------------------------------
# Shared paths, sources and helpers for the Basketball-Reference value study.
# Sourced by 01_acquire.R, 02_clean.R and 03_analyze.R. Nothing here touches
# the network; it only declares where things live.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(stringr)
  library(readr)
  library(tibble)
})

POST_DIR    <- here("blog", "posts", "post2")
RAW_DIR     <- file.path(POST_DIR, "data", "raw")
DERIVED_DIR <- file.path(POST_DIR, "data", "derived")
TABLE_DIR   <- file.path(POST_DIR, "results", "tables")
FIGURE_DIR  <- file.path(POST_DIR, "results", "figures")

for (d in c(RAW_DIR, DERIVED_DIR, TABLE_DIR, FIGURE_DIR)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# Sources -----------------------------------------------------------------
# Season labels follow Basketball-Reference: "2026" is the 2025-26 season.
PERF_SEASON  <- 2026L   # production we observe
PRIOR_SEASON <- 2025L   # previous season, used to stabilise the estimate
SALARY_YEAR  <- "2026-27"  # the contract year we are pricing

SOURCES <- tribble(
  ~key,            ~url,                                                             ~raw_file,
  "advanced_2026", "https://www.basketball-reference.com/leagues/NBA_2026_advanced.html", "bbref_advanced_2026.html",
  "advanced_2025", "https://www.basketball-reference.com/leagues/NBA_2025_advanced.html", "bbref_advanced_2025.html",
  "contracts",     "https://www.basketball-reference.com/contracts/players.html",         "bbref_contracts_players.html"
) |>
  mutate(raw_path = file.path(RAW_DIR, raw_file))

# Derived + result files
PLAYERS_FILE  <- file.path(DERIVED_DIR, "player_seasons.csv")
SALARY_FILE   <- file.path(DERIVED_DIR, "player_salaries.csv")
ANALYSIS_FILE <- file.path(DERIVED_DIR, "analysis_data.csv")
METADATA_FILE <- file.path(RAW_DIR, "metadata.csv")

# Politeness --------------------------------------------------------------
# robots.txt for basketball-reference.com allows /leagues/ and /contracts/
# and asks for Crawl-delay: 3. We request three pages, once, and cache them.
CRAWL_DELAY <- 4
USER_AGENT  <- paste(
  "KyleTong-coursework/1.0 (AEDS 6400 class project;",
  "junhaot555@gmail.com) rvest"
)

# Analysis choices --------------------------------------------------------
MIN_MINUTES   <- 500     # a player needs a real sample before we price him
PRIOR_WEIGHT  <- 1 / 3   # weight on the previous season's rate stats
MIN_SALARY    <- 1.4e6   # ~2026-27 one-year veteran minimum, in dollars

# Helpers -----------------------------------------------------------------

# Strip Basketball-Reference footnote markers and stray whitespace.
clean_text <- function(x) {
  x |>
    str_remove_all("\\[[^\\]]*\\]") |>
    str_remove_all("\\*") |>
    str_squish()
}

# Player names are the join key, so normalise the things that differ between
# a stats page and a contracts page: accents, punctuation, generational
# suffixes, case.
normalise_name <- function(x) {
  x |>
    clean_text() |>
    stringi::stri_trans_general("Latin-ASCII") |>
    str_remove("\\s+(Jr|Sr|II|III|IV)\\.?$") |>
    str_remove_all("[.'`]") |>
    str_replace_all("-", " ") |>
    str_to_lower() |>
    str_squish()
}
