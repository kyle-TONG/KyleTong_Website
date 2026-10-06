# 01_acquire.R -----------------------------------------------------------
# Pull the six FRED series behind the productivity-pay decomposition and save
# them as one tidy csv plus a provenance record.
#
#   Rscript blog/posts/post4/R/01_acquire.R
#
# Needs a free FRED API key from
# https://fred.stlouisfed.org/docs/api/api_key.html, stored in ~/.Renviron as
#   FRED_API_KEY=your_key_here

suppressPackageStartupMessages({
  library(here)
  library(fredr)
  library(dplyr)
  library(purrr)
  library(readr)
  library(tibble)
})

RAW_DIR <- here("blog", "posts", "post4", "data", "raw")
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

api_key <- Sys.getenv("FRED_API_KEY")
if (!nzchar(api_key)) {
  stop("FRED_API_KEY is not set. Run usethis::edit_r_environ(), add\n",
       "  FRED_API_KEY=your_key_here\n",
       "save the file, restart R, and run this script again.")
}
fredr_set_key(api_key)

START <- as.Date("1947-01-01")

# Two of these are monthly and four are quarterly. FRED aggregates the monthly
# ones to quarterly averages server-side, so the panel below is one frequency
# and the aggregation rule is recorded rather than improvised here.
SERIES <- tribble(
  ~id,         ~role,
  "OPHNFB",    "productivity",
  "COMPNFB",   "hourly compensation, nominal",
  "IPDNBS",    "output price deflator",
  "COMPRNFB",  "hourly compensation, CPI-deflated",
  "CPIAUCSL",  "consumer price index",
  "AHETPI",    "production worker hourly earnings, nominal"
)

pull <- function(id) {
  fredr(series_id = id, observation_start = START, frequency = "q",
        aggregation_method = "avg") |>
    transmute(series_id = id, date, value)
}

observations <- map(SERIES$id, pull) |> list_rbind()

stopifnot(nrow(observations) > 1000)
stopifnot(setequal(unique(observations$series_id), SERIES$id))

write_csv(observations, file.path(RAW_DIR, "fred_observations.csv"))

# Provenance: titles, units and coverage come from FRED itself, so the record
# describes what was actually served rather than what was expected.
metadata <- map(SERIES$id, fredr_series) |>
  list_rbind() |>
  select(id, title, units, seasonal_adjustment, frequency,
         observation_start, observation_end, last_updated) |>
  left_join(SERIES, by = "id") |>
  mutate(source      = "FRED, Federal Reserve Bank of St. Louis",
         source_url  = paste0("https://fred.stlouisfed.org/series/", id),
         accessed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))

write_csv(metadata, file.path(RAW_DIR, "metadata.csv"))

message(sprintf("%d observations, %d series, through %s",
                nrow(observations), n_distinct(observations$series_id),
                max(observations$date)))
print(select(metadata, id, role, observation_end))
