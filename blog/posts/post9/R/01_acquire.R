# 01_acquire.R -----------------------------------------------------------
# Download daily prices for the 100-stock universe used in class and for SPY,
# with a fixed end date so every number in the post can be reproduced.
#
#   Rscript blog/posts/post9/R/01_acquire.R           # use the cache
#   Rscript blog/posts/post9/R/01_acquire.R --force   # re-download
#
# Source: Yahoo Finance via tidyquant::tq_get(). The original class model uses
# data from 2022; the history back to 2012 is for the longer training window
# tried in 03_improved.R.

suppressPackageStartupMessages({
  library(here)
  library(tidyquant)
  library(dplyr)
  library(readr)
  library(tibble)
})

RAW_DIR <- here("blog", "posts", "post9", "data", "raw")
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

START <- "2012-01-01"
END   <- "2026-11-14"   # exclusive, so the last trading day is Fri 2026-11-13

# The universe from the class script, unchanged.
TICKERS <- c(
  "AAPL","MSFT","NVDA","GOOG","META","AMZN","AVGO","ORCL","ADBE","CRM",
  "CSCO","AMD","INTC","QCOM","TXN","IBM","NOW","INTU","AMAT","MU",
  "JPM","BAC","WFC","GS","MS","BLK","C","SCHW","SPGI","AXP",
  "USB","PNC","TFC","COF",
  "UNH","JNJ","LLY","PFE","MRK","ABBV","TMO","DHR","ABT","BMY",
  "AMGN","GILD","CVS","ISRG","MDT",
  "TSLA","HD","MCD","NKE","SBUX","LOW","TJX","BKNG","CMG","ORLY",
  "WMT","COST","PG","KO","PEP","PM","MO","CL","EL",
  "CAT","GE","HON","UPS","BA","RTX","DE","LMT","MMM","ETN",
  "XOM","CVX","COP","SLB","EOG",
  "NFLX","DIS","CMCSA","TMUS","VZ",
  "AMT","PLD","NEE","DUK","SO","LIN","APD"
)

prices_file <- file.path(RAW_DIR, "prices.csv.gz")
spy_file    <- file.path(RAW_DIR, "spy.csv.gz")
force <- "--force" %in% commandArgs(trailingOnly = TRUE)

if (!file.exists(prices_file) || force) {
  prices <- tq_get(TICKERS, from = START, to = END)
  write_csv(prices, prices_file)
}
if (!file.exists(spy_file) || force) {
  spy <- tq_get("SPY", from = START, to = END)
  write_csv(spy, spy_file)
}

prices <- read_csv(prices_file, show_col_types = FALSE)
spy    <- read_csv(spy_file, show_col_types = FALSE)

coverage <- prices |>
  group_by(symbol) |>
  summarise(first = min(date), last = max(date), days = n(), .groups = "drop")

missing <- setdiff(TICKERS, coverage$symbol)
if (length(missing) > 0) warning("no data for: ", paste(missing, collapse = ", "))
stopifnot(length(missing) == 0, max(spy$date) == as.Date("2026-11-13"))

write_csv(tibble(
  source      = "Yahoo Finance via tidyquant::tq_get",
  tickers     = length(TICKERS),
  from        = START,
  to          = "2026-11-13",
  accessed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
), file.path(RAW_DIR, "metadata.csv"))
write_csv(coverage, file.path(RAW_DIR, "coverage.csv"))

message(sprintf("%d tickers, %s rows; SPY through %s",
                n_distinct(prices$symbol), format(nrow(prices), big.mark = ","),
                max(spy$date)))
print(coverage |> filter(first > as.Date("2012-01-10")))
