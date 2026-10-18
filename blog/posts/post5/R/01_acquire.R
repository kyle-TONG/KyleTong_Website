# 01_acquire.R -----------------------------------------------------------
# Pull 2020-2024 ACS 5-year estimates for every census tract in Philadelphia,
# plus the tract boundaries, and save both with a provenance record.
#
#   Rscript blog/posts/post5/R/01_acquire.R
#
# Needs a free Census API key from
# https://api.census.gov/data/key_signup.html, stored in ~/.Renviron as
#   CENSUS_API_KEY=your_key_here

suppressPackageStartupMessages({
  library(here)
  library(tidycensus)
  library(tigris)
  library(sf)
  library(dplyr)
  library(readr)
  library(tibble)
})

RAW_DIR <- here("blog", "posts", "post5", "data", "raw")
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

api_key <- Sys.getenv("CENSUS_API_KEY")
if (!nzchar(api_key)) {
  stop("CENSUS_API_KEY is not set. Run usethis::edit_r_environ(), add\n",
       "  CENSUS_API_KEY=your_key_here\n",
       "save the file, restart R, and run this script again.")
}

# Tracts are too small for the 1-year ACS, so this is the 2020-2024 5-year
# release, the most recent available.
ACS_YEAR <- 2024
STATE    <- "PA"
COUNTY   <- "Philadelphia"

# Variables. Names on the left become column prefixes; tidycensus appends E
# (estimate) and M (90 percent margin of error) to each.
VARIABLES <- c(
  pop       = "B01003_001",  # total population
  med_inc   = "B19013_001",  # median household income, 2024 dollars
  pov_tot   = "B14006_001",  # population 3+ with poverty status determined
  pov_below = "B14006_002",  #   of whom below the poverty line
  bel_ug    = "B14006_009",  #   below poverty, enrolled undergraduate
  bel_grad  = "B14006_010",  #   below poverty, enrolled graduate/professional
  abv_ug    = "B14006_019",  #   at or above poverty, enrolled undergraduate
  abv_grad  = "B14006_020"   #   at or above poverty, enrolled graduate/professional
)

# tidycensus 1.8.1 does not pick the key up from the environment on its own,
# and the 2024 endpoint rejects keyless requests, so it is passed explicitly.
acs <- get_acs(geography = "tract", variables = VARIABLES,
               state = STATE, county = COUNTY, year = ACS_YEAR,
               survey = "acs5", output = "wide", key = api_key)

stopifnot(nrow(acs) > 350, all(c("pov_totE", "bel_ugE", "abv_gradE") %in% names(acs)))
write_csv(acs, file.path(RAW_DIR, "acs_tracts_2024.csv"))

# Boundaries: cartographic boundary files (cb = TRUE) are clipped to the
# shoreline, so the Delaware and Schuylkill read as rivers rather than as
# tract area.
options(tigris_use_cache = TRUE)
tracts_sf <- tracts(state = STATE, county = COUNTY, year = ACS_YEAR,
                    cb = TRUE, progress_bar = FALSE) |>
  select(GEOID, NAMELSAD, ALAND)

stopifnot(nrow(tracts_sf) == nrow(acs))
st_write(tracts_sf, file.path(RAW_DIR, "phl_tracts_2024.gpkg"),
         delete_dsn = TRUE, quiet = TRUE)

metadata <- tibble(
  source      = c("Census Bureau, American Community Survey 5-year",
                  "Census Bureau, TIGER/Line cartographic boundary files"),
  source_url  = c("https://api.census.gov/data/2024/acs/acs5",
                  "https://www2.census.gov/geo/tiger/GENZ2024/"),
  vintage     = c("2020-2024", "2024"),
  geography   = "census tract, Philadelphia County, PA",
  file        = c("acs_tracts_2024.csv", "phl_tracts_2024.gpkg"),
  variables   = c(paste(names(VARIABLES), VARIABLES, sep = "=", collapse = " "),
                  "GEOID NAMELSAD ALAND geometry"),
  rows        = c(nrow(acs), nrow(tracts_sf)),
  accessed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
)

write_csv(metadata, file.path(RAW_DIR, "metadata.csv"))
message(sprintf("%d tracts, ACS %d-%d", nrow(acs), ACS_YEAR - 4, ACS_YEAR))
