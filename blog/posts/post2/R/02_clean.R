# 02_clean.R -------------------------------------------------------------
# Parse the raw HTML snapshots, join production to salary, and write one tidy
# file for the post. Reads only from data/raw/, writes only to data/derived/.

suppressPackageStartupMessages({
  library(here)
  library(rvest)
  library(dplyr)
  library(stringr)
  library(readr)
})

POST_DIR    <- here("blog", "posts", "post2")
RAW_DIR     <- file.path(POST_DIR, "data", "raw")
DERIVED_DIR <- file.path(POST_DIR, "data", "derived")
dir.create(DERIVED_DIR, recursive = TRUE, showWarnings = FALSE)

MIN_MINUTES <- 500  # a player needs a real sample before we price him

# Names carry footnote markers; the join key also has to survive accents,
# punctuation and generational suffixes.
clean_text <- function(x) str_squish(str_remove_all(x, "\\[[^\\]]*\\]|\\*"))

name_key <- function(x) {
  x |>
    clean_text() |>
    stringi::stri_trans_general("Latin-ASCII") |>
    str_remove("\\s+(Jr|Sr|II|III|IV)\\.?$") |>
    str_remove_all("[.'`]") |>
    str_replace_all("-", " ") |>
    str_to_lower()
}

# Production: 2025-26 advanced stats -------------------------------------

advanced <- read_html(file.path(RAW_DIR, "bbref_advanced_2026.html")) |>
  html_element("#advanced") |>
  html_table()

players <- advanced |>
  transmute(rk     = Rk,
            player = clean_text(Player),
            age    = as.integer(Age),
            team   = Team,
            pos    = Pos,
            g      = as.integer(G),
            mp     = as.integer(MP),
            bpm    = as.numeric(BPM),
            vorp   = as.numeric(VORP)) |>
  filter(player != "", player != "Player")

# A player traded mid-season appears once per team plus a combined "2TM" row,
# all sharing a rank. Keep the combined row: it is his whole season.
players <- players |>
  group_by(rk) |>
  filter(!any(str_detect(team, "^\\d+TM$")) | str_detect(team, "^\\d+TM$")) |>
  ungroup()

# Validation. VORP is a deterministic function of BPM and minutes, so
# recomputing it catches shifted columns and numbers parsed as text.
vorp_gap <- with(players, abs((bpm + 2) * mp / (48 * 82) - vorp))
stopifnot(max(vorp_gap, na.rm = TRUE) < 0.15)

# Salary: 2026-27 contracts ----------------------------------------------
# The contracts table has a two-row header, so html_table() returns the real
# column names as the first row of data.

contracts <- read_html(file.path(RAW_DIR, "bbref_contracts_players.html")) |>
  html_element("#player-contracts") |>
  html_table()

names(contracts) <- as.character(contracts[1, ])

salaries <- contracts[-1, ] |>
  transmute(player = clean_text(Player),
            salary = parse_number(`2026-27`)) |>   # "$62,587,158" -> 62587158
  filter(player != "", player != "Player", !is.na(salary)) |>
  mutate(key = name_key(player)) |>
  arrange(key, desc(salary)) |>
  distinct(key, .keep_all = TRUE)

# Join and save ----------------------------------------------------------

analysis <- players |>
  mutate(key = name_key(player)) |>
  inner_join(select(salaries, key, salary), by = "key") |>
  mutate(salary_m = salary / 1e6,
         band     = cut(salary_m, c(0, 5, 15, 30, Inf),
                        labels = c("Under $5M", "$5-15M", "$15-30M",
                                   "Over $30M")))

message(sprintf("matched %d of %d contracts (%.0f%%)",
                nrow(analysis), nrow(salaries),
                100 * nrow(analysis) / nrow(salaries)))

analysis <- filter(analysis, mp >= MIN_MINUTES)
stopifnot(nrow(analysis) > 200)

write_csv(analysis, file.path(DERIVED_DIR, "analysis_data.csv"))
write_csv(anti_join(salaries, players |> mutate(key = name_key(player)), by = "key") |>
            arrange(desc(salary)),
          file.path(DERIVED_DIR, "unmatched_contracts.csv"))

message(sprintf("wrote %d players with at least %d minutes",
                nrow(analysis), MIN_MINUTES))
