# 01_acquire.R -----------------------------------------------------------
# Download two Basketball-Reference pages and save them as raw HTML snapshots
# plus a provenance record. Run once; 02_clean.R parses the snapshots, so
# nothing downstream needs the network.
#
#   Rscript blog/posts/post2/R/01_acquire.R          # use the cache
#   Rscript blog/posts/post2/R/01_acquire.R --force  # re-download

suppressPackageStartupMessages({
  library(here)
  library(rvest)
  library(httr)
  library(dplyr)
  library(readr)
  library(tibble)
})

RAW_DIR <- here("blog", "posts", "post2", "data", "raw")
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

# robots.txt on basketball-reference.com allows /leagues/ and /contracts/ and
# asks for Crawl-delay: 3. Two requests, four seconds apart, with a user agent
# that says who is asking.
CRAWL_DELAY <- 4
USER_AGENT  <- "KyleTong-coursework/1.0 (AEDS 6400 class project) rvest"

sources <- tribble(
  ~key,        ~url,                                                                  ~file,
  "advanced",  "https://www.basketball-reference.com/leagues/NBA_2026_advanced.html", "bbref_advanced_2026.html",
  "contracts", "https://www.basketball-reference.com/contracts/players.html",         "bbref_contracts_players.html"
) |>
  mutate(path = file.path(RAW_DIR, file))

force_refresh <- "--force" %in% commandArgs(trailingOnly = TRUE)

for (i in seq_len(nrow(sources))) {
  path <- sources$path[i]

  if (file.exists(path) && !force_refresh) {
    message("cached   ", sources$file[i])
    next
  }

  Sys.sleep(CRAWL_DELAY)
  message("fetching ", sources$url[i])
  resp <- GET(sources$url[i], user_agent(USER_AGENT), timeout(60))
  stopifnot(status_code(resp) == 200)
  xml2::write_html(read_html(resp), path)
}

# Provenance: what was requested, from where, and when.
metadata <- sources |>
  transmute(source      = "Basketball-Reference",
            source_url  = url,
            raw_file    = file,
            accessed_at = format(file.mtime(path), "%Y-%m-%d %H:%M:%S %Z"),
            bytes       = file.size(path))

write_csv(metadata, file.path(RAW_DIR, "metadata.csv"))

stopifnot(all(file.exists(sources$path)), all(metadata$bytes > 1e5))
print(metadata)
