# 01_acquire.R -----------------------------------------------------------
# Download three Basketball-Reference pages, save the raw HTML snapshots and
# a provenance record. Run once; 02_clean.R parses the snapshots, so nothing
# downstream needs the network.
#
#   Rscript blog/posts/post2/R/01_acquire.R          # use the cache
#   Rscript blog/posts/post2/R/01_acquire.R --force  # re-download

source(here::here("blog", "posts", "post2", "R", "00_config.R"))

suppressPackageStartupMessages({
  library(rvest)
  library(httr)
  library(xml2)
})

force_refresh <- "--force" %in% commandArgs(trailingOnly = TRUE)

# One request, one snapshot. The delay is the Crawl-delay basketball-
# reference.com publishes in robots.txt; the identifying user agent means the
# site can see who is asking and block us if it wants to.
fetch_snapshot <- function(url, path, force = FALSE) {
  if (file.exists(path) && !force) {
    message("cached  ", basename(path))
    return(invisible(FALSE))
  }

  Sys.sleep(CRAWL_DELAY)
  message("fetching ", url)
  resp <- GET(url, user_agent(USER_AGENT), timeout(60))

  if (status_code(resp) != 200) {
    stop("request failed with status ", status_code(resp), ": ", url)
  }

  page <- read_html(resp)
  write_html(page, path)
  invisible(TRUE)
}

for (i in seq_len(nrow(SOURCES))) {
  fetch_snapshot(SOURCES$url[i], SOURCES$raw_path[i], force = force_refresh)
}

# Provenance: what was requested, from where, when, and how big the answer was.
metadata <- SOURCES |>
  transmute(
    key,
    source      = "Basketball-Reference",
    source_url  = url,
    raw_file,
    accessed_at = format(file.mtime(raw_path), "%Y-%m-%d %H:%M:%S %Z"),
    bytes       = file.size(raw_path)
  )

write_csv(metadata, METADATA_FILE)

# Validation: a snapshot that is missing the table we came for is a failure we
# want to hear about now, not three scripts later.
stopifnot(all(file.exists(SOURCES$raw_path)))
stopifnot(all(metadata$bytes > 1e5))

expected_tables <- c(advanced_2026 = "#advanced",
                     advanced_2025 = "#advanced",
                     contracts     = "#player-contracts")

for (key in names(expected_tables)) {
  path <- SOURCES$raw_path[SOURCES$key == key]
  node <- read_html(path) |> html_element(expected_tables[[key]])
  if (inherits(node, "xml_missing")) {
    stop("snapshot ", key, " has no ", expected_tables[[key]], " table; ",
         "the page layout probably changed")
  }
}

message("snapshots ok -> ", RAW_DIR)
print(metadata)
