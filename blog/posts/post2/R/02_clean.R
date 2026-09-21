# 02_clean.R -------------------------------------------------------------
# Parse the raw HTML snapshots into tidy csv files. Reads only from
# data/raw/, writes only to data/derived/. No network access.

source(here::here("blog", "posts", "post2", "R", "00_config.R"))

suppressPackageStartupMessages({
  library(rvest)
  library(xml2)
  library(tidyr)
})

snapshot <- function(key) {
  read_html(SOURCES$raw_path[SOURCES$key == key])
}

# Basketball-Reference hides some secondary tables inside HTML comments, so a
# plain html_element() finds nothing. Look in the visible document first, then
# inside the comments. The 2026 pages happen to expose both tables we need,
# but the fallback keeps the script working if that changes back.
find_table <- function(page, css) {
  node <- html_element(page, css)
  if (!inherits(node, "xml_missing")) return(node)

  commented <- xml_find_all(page, "//comment()") |>
    xml_text() |>
    keep_containing(css)

  if (length(commented) == 0) {
    stop("no table matching ", css, " in the snapshot")
  }
  html_element(read_html(commented[[1]]), css)
}

keep_containing <- function(x, css) {
  id <- str_remove(css, "^#")
  x[str_detect(x, fixed(paste0("id=\"", id, "\"")))]
}

# Advanced season tables --------------------------------------------------

read_advanced <- function(key, season) {
  raw <- find_table(snapshot(key), "#advanced") |>
    html_table()

  raw |>
    rename(pos = Pos, team = Team) |>
    transmute(
      season,
      rk     = Rk,
      player = clean_text(Player),
      age    = as.integer(Age),
      team   = clean_text(team),
      pos    = clean_text(pos),
      g      = as.integer(G),
      mp     = as.integer(MP),
      per    = as.numeric(PER),
      usg    = as.numeric(`USG%`),
      ws     = as.numeric(WS),
      ws48   = as.numeric(`WS/48`),
      bpm    = as.numeric(BPM),
      vorp   = as.numeric(VORP)
    ) |>
    filter(player != "", player != "Player", pos != "")
}

# A player traded mid-season appears once per team plus a combined "2TM"/"3TM"
# row, all sharing one rank. Keep the combined row: it is his whole season.
collapse_traded <- function(df) {
  df |>
    group_by(season, rk) |>
    mutate(traded = any(str_detect(team, "^\\d+TM$"))) |>
    filter(!traded | str_detect(team, "^\\d+TM$")) |>
    ungroup() |>
    select(-traded)
}

players <- bind_rows(
  read_advanced("advanced_2026", PERF_SEASON),
  read_advanced("advanced_2025", PRIOR_SEASON)
) |>
  collapse_traded() |>
  mutate(
    player_key = normalise_name(player),
    pos_group  = case_when(
      pos %in% c("PG", "SG") ~ "Guard",
      pos == "SF"            ~ "Small forward",
      pos == "PF"            ~ "Power forward",
      pos == "C"             ~ "Center",
      TRUE                   ~ "Other"
    )
  )

# Validation. VORP is a deterministic function of BPM and minutes:
#   VORP = (BPM + 2) * MP / (48 * 82)
# so recomputing it is a cheap check that the columns landed where we think
# they did and that nothing was parsed as text.
vorp_check <- players |>
  filter(season == PERF_SEASON, mp > 0) |>
  mutate(vorp_hat = (bpm + 2) * mp / (48 * 82),
         gap      = abs(vorp_hat - vorp))

stopifnot(nrow(players) > 0)
stopifnot(max(vorp_check$gap, na.rm = TRUE) < 0.15)
stopifnot(!anyDuplicated(players[c("season", "player_key")]))

write_csv(players, PLAYERS_FILE)

# Contracts ---------------------------------------------------------------
# The contracts table has a two-row header, so html_table() returns the real
# column names as the first data row.

contracts_raw <- find_table(snapshot("contracts"), "#player-contracts") |>
  html_table()

names(contracts_raw) <- as.character(contracts_raw[1, ])
contracts_raw <- contracts_raw[-1, ]

salaries <- contracts_raw |>
  filter(Player != "", Player != "Player") |>
  transmute(
    player     = clean_text(Player),
    team       = clean_text(Tm),
    salary     = parse_number(.data[[SALARY_YEAR]]),
    guaranteed = parse_number(Guaranteed),
    years_left = rowSums(across(all_of(c("2026-27", "2027-28", "2028-29",
                                         "2029-30", "2030-31", "2031-32")),
                                ~ !is.na(parse_number(.x))))
  ) |>
  filter(!is.na(salary)) |>
  mutate(player_key = normalise_name(player))

# Two-way and duplicate listings: keep the larger salary for a repeated name.
salaries <- salaries |>
  arrange(player_key, desc(salary)) |>
  distinct(player_key, .keep_all = TRUE)

stopifnot(nrow(salaries) > 300)
stopifnot(all(salaries$salary > 0))

write_csv(salaries, SALARY_FILE)

# Join --------------------------------------------------------------------
# Production comes from the season just played; salary is what the player is
# owed for the season about to start.

perf  <- players |> filter(season == PERF_SEASON)
prior <- players |>
  filter(season == PRIOR_SEASON) |>
  select(player_key, bpm_prior = bpm, mp_prior = mp)

analysis <- perf |>
  select(player, player_key, age, team, pos, pos_group, g, mp, per, usg,
         ws, ws48, bpm, vorp) |>
  inner_join(salaries |> select(player_key, salary, guaranteed, years_left,
                                salary_team = team),
             by = "player_key") |>
  left_join(prior, by = "player_key") |>
  mutate(
    # Blend the two seasons of BPM, weighting the prior year less, then put
    # the blend back on the VORP scale at this season's minutes. One season of
    # BPM is noisy; this pulls small samples toward a fuller picture.
    w_now      = mp,
    w_prior    = coalesce(mp_prior, 0) * PRIOR_WEIGHT,
    bpm_blend  = (bpm * w_now + coalesce(bpm_prior, bpm) * w_prior) /
                 (w_now + w_prior),
    proj_vorp  = (bpm_blend + 2) * mp / (48 * 82),
    salary_m   = salary / 1e6,
    age_band   = cut(age, breaks = c(0, 23, 26, 29, 32, 99),
                     labels = c("22 and under", "23-25", "26-28",
                                "29-31", "32+"),
                     right = TRUE)
  ) |>
  select(-w_now, -w_prior)

match_rate <- nrow(analysis) / nrow(salaries)
message(sprintf("matched %d of %d contracts (%.1f%%)",
                nrow(analysis), nrow(salaries), 100 * match_rate))

unmatched <- salaries |>
  anti_join(perf, by = "player_key") |>
  arrange(desc(salary))

write_csv(unmatched, file.path(DERIVED_DIR, "unmatched_contracts.csv"))

write_csv(tibble(contracts   = nrow(salaries),
                 matched     = nrow(analysis),
                 match_rate  = match_rate,
                 min_minutes = MIN_MINUTES,
                 analysed    = sum(analysis$mp >= MIN_MINUTES)),
          file.path(DERIVED_DIR, "match_summary.csv"))
stopifnot(match_rate > 0.75)

analysis <- analysis |> filter(mp >= MIN_MINUTES)
stopifnot(nrow(analysis) > 200)

write_csv(analysis, ANALYSIS_FILE)

message(sprintf("analysis sample: %d players, %d with >= %d minutes",
                nrow(analysis), sum(analysis$mp >= MIN_MINUTES), MIN_MINUTES))
