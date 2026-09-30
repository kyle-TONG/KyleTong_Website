# 01_acquire.R -----------------------------------------------------------
# Define, submit and download an IPUMS CPS extract: March Basic Monthly
# samples, 1990 to the present, with the variables needed to compute
# labour-force participation by age.
#
#   Rscript blog/posts/post3/R/01_acquire.R
#
# Needs a free IPUMS account and an API key from
# https://account.ipums.org/api_keys, stored in ~/.Renviron as
#   IPUMS_API_KEY=your_key_here
# The key is never written into this script or into the repository.

suppressPackageStartupMessages({
  library(here)
  library(ipumsr)
  library(dplyr)
  library(readr)
  library(tibble)
})

RAW_DIR <- here("blog", "posts", "post3", "data", "raw")
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

api_key <- Sys.getenv("IPUMS_API_KEY")
if (!nzchar(api_key)) {
  stop("IPUMS_API_KEY is not set. Run usethis::edit_r_environ(), add\n",
       "  IPUMS_API_KEY=your_key_here\n",
       "save the file, restart R, and run this script again.")
}

FIRST_YEAR <- 1990
VARIABLES  <- c("AGE", "SEX", "LABFORCE", "EMPSTAT", "WTFINL")

# Samples. Basic Monthly CPS sample ids look like cps2024_03b; the ASEC
# supplement uses an "s" suffix and a different weight, so the pattern is
# checked against the live metadata rather than hard-coded.
samples <- get_sample_info("cps")

march_basic <- samples |>
  filter(grepl("^cps[0-9]{4}_03b$", name)) |>
  mutate(year = as.integer(substr(name, 4, 7))) |>
  filter(year >= FIRST_YEAR) |>
  arrange(year)

stopifnot(nrow(march_basic) > 20)
message(sprintf("%d March samples, %d to %d",
                nrow(march_basic), min(march_basic$year), max(march_basic$year)))

# Submit and wait. IPUMS builds the extract server-side; this usually takes a
# few minutes. Downloaded files are cached, so a re-run does not resubmit.
ddi_existing <- list.files(RAW_DIR, pattern = "\\.xml$", full.names = TRUE)

if (length(ddi_existing) == 0) {
  extract <- define_extract_micro(
    collection  = "cps",
    description = "March Basic Monthly CPS, 1990-present: LFP by age",
    samples     = march_basic$name,
    variables   = VARIABLES
  )

  submitted <- submit_extract(extract)
  message("submitted extract ", submitted$collection, ":", submitted$number)

  ready <- wait_for_extract(submitted)
  paths <- download_extract(ready, download_dir = RAW_DIR, progress = TRUE)
  message("downloaded: ", paste(basename(paths), collapse = ", "))
} else {
  message("cached extract found in data/raw, skipping download")
}

# Provenance ---------------------------------------------------------------

ddi_file <- list.files(RAW_DIR, pattern = "\\.xml$", full.names = TRUE)[1]
ddi      <- read_ipums_ddi(ddi_file)

metadata <- tibble(
  source      = "IPUMS CPS",
  source_url  = "https://cps.ipums.org/cps/",
  collection  = "cps",
  samples     = paste(range(march_basic$year), collapse = "-"),
  n_samples   = nrow(march_basic),
  variables   = paste(VARIABLES, collapse = " "),
  ddi_file    = basename(ddi_file),
  accessed_at = format(file.mtime(ddi_file), "%Y-%m-%d %H:%M:%S %Z")
)

write_csv(metadata, file.path(RAW_DIR, "metadata.csv"))
print(metadata)

# The extract is large and IPUMS asks users to register before downloading, so
# data/raw is kept out of git. 02_clean.R writes the aggregated tables instead.
message("raw microdata stays local; run 02_clean.R next")
