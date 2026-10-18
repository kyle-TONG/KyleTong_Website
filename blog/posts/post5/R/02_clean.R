# 02_clean.R -------------------------------------------------------------
# Turn raw ACS counts into two comparable poverty rates, one for everyone and
# one excluding college and graduate students, attach them to tract
# boundaries, and flag the student tracts around each campus. Reads only from
# data/raw/, writes to data/derived/.

suppressPackageStartupMessages({
  library(here)
  library(sf)
  library(dplyr)
  library(readr)
})

POST_DIR    <- here("blog", "posts", "post5")
RAW_DIR     <- file.path(POST_DIR, "data", "raw")
DERIVED_DIR <- file.path(POST_DIR, "data", "derived")
dir.create(DERIVED_DIR, recursive = TRUE, showWarnings = FALSE)

# Projected CRS for anything involving distance: UTM zone 18N, in metres.
# Latitude and longitude are angles, and a "distance" computed in them is
# not a distance.
CRS_M <- 32618

MIN_POP       <- 500   # below this a tract rate is mostly sampling noise
STUDENT_SHARE <- 0.25  # a tract counts as a student tract above this
CAMPUS_RADIUS <- 1000  # metres from a campus centre

acs <- read_csv(file.path(RAW_DIR, "acs_tracts_2024.csv"),
                col_types = cols(GEOID = col_character()))

tracts <- st_read(file.path(RAW_DIR, "phl_tracts_2024.gpkg"), quiet = TRUE) |>
  st_transform(CRS_M)

# Counts become rates. A map of counts mostly shows which tracts are large.
# Both poverty rates come from the same table (B14006), so they share a
# universe, people 3 and over whose poverty status is determined, and differ
# only in whether college and graduate students are counted. Poverty status is
# not determined for people in dormitories, so student_share here is the share
# of off-campus students, which is the group that can move a tract's poverty
# rate at all.
rates <- acs |>
  transmute(
    GEOID,
    pop          = popE,
    med_inc      = med_incE,
    pov_universe = pov_totE,
    pov_poor     = pov_belowE,
    col_pop      = bel_ugE + bel_gradE + abv_ugE + abv_gradE,
    col_poor     = bel_ugE + bel_gradE,
    noncol_pop   = pov_universe - col_pop,
    noncol_poor  = pov_poor - col_poor,
    student_share = col_pop / pov_universe,
    pov_all      = if_else(pov_universe >= MIN_POP, pov_poor / pov_universe, NA_real_),
    pov_noncol   = if_else(noncol_pop   >= MIN_POP, noncol_poor / noncol_pop, NA_real_)
  )

# Campuses. Penn and Drexel sit next to each other in University City and are
# treated as one area.
campuses <- tibble(
  campus = c("Penn", "Drexel", "Temple"),
  area   = c("University City", "University City", "Temple"),
  lon    = c(-75.1932, -75.1899, -75.1554),
  lat    = c( 39.9522,  39.9566,  39.9812)
) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
  st_transform(CRS_M)

dist <- st_distance(st_centroid(st_geometry(tracts)), campuses)

tracts <- tracts |>
  mutate(nearest_area = campuses$area[apply(dist, 1, which.min)],
         campus_m     = as.numeric(apply(dist, 1, min))) |>
  left_join(rates, by = "GEOID") |>
  mutate(
    student_tract = !is.na(student_share) & pov_universe >= MIN_POP &
                    student_share >= STUDENT_SHARE,
    campus_area   = if_else(student_tract & campus_m <= CAMPUS_RADIUS,
                            nearest_area, NA_character_)
  )

# Validation. The college and non-college pieces have to add back to the
# whole, every rate has to be a proportion, and the campus flag has to find
# tracts at both campuses.
stopifnot(nrow(tracts) == nrow(acs))
stopifnot(all(tracts$col_pop + tracts$noncol_pop == tracts$pov_universe, na.rm = TRUE))
stopifnot(all(tracts$col_poor + tracts$noncol_poor == tracts$pov_poor, na.rm = TRUE))
for (v in c("student_share", "pov_all", "pov_noncol")) {
  stopifnot(all(tracts[[v]] >= 0 & tracts[[v]] <= 1, na.rm = TRUE))
}
stopifnot(setequal(unique(na.omit(tracts$campus_area)),
                   c("University City", "Temple")))

st_write(tracts, file.path(DERIVED_DIR, "phl_tracts.gpkg"),
         delete_dsn = TRUE, quiet = TRUE)
write_csv(st_drop_geometry(tracts), file.path(DERIVED_DIR, "phl_tracts.csv"))

# Pooled rates, computed from counts rather than averaged across tracts.
pooled <- st_drop_geometry(tracts) |>
  mutate(group = coalesce(campus_area, "Rest of city")) |>
  group_by(group) |>
  summarise(tracts      = n(),
            pov_all     = sum(pov_poor, na.rm = TRUE) / sum(pov_universe, na.rm = TRUE),
            pov_noncol  = sum(noncol_poor, na.rm = TRUE) / sum(noncol_pop, na.rm = TRUE),
            pov_college = sum(col_poor, na.rm = TRUE) / sum(col_pop, na.rm = TRUE),
            .groups     = "drop")

write_csv(pooled, file.path(DERIVED_DIR, "pooled_rates.csv"))

message(sprintf("%d tracts; %d student tracts; %d campus tracts",
                nrow(tracts), sum(tracts$student_tract),
                sum(!is.na(tracts$campus_area))))
print(pooled |> mutate(across(starts_with("pov"), ~ round(100 * .x, 1))))
