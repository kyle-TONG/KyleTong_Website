# 03_improved.R ----------------------------------------------------------
# A revised gradient boosting model, evaluated on the same out-of-sample
# months as the class model (formation dates January 2024 to October 2026).
#
# Changes from the class model:
#   features   only stationary signals, ranked across stocks each month;
#              no raw price or volume levels
#   target     20-day return relative to the cross-sectional average
#   sampling   one observation per stock per month, so targets do not overlap
#   training   2013 onward, expanding window, refit every month, and only on
#              rows whose 20-day target had ended before the formation date
#   tuning     hyperparameters chosen on 2019-2023 only, before the test period
#   portfolio  top 10, equal weight, weights that sum to one
#
# Reads data/raw/, writes data/derived/.

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(slider)
  library(xgboost)
})

POST    <- here("blog", "posts", "post9")
RAW     <- file.path(POST, "data", "raw")
DERIVED <- file.path(POST, "data", "derived")

prices <- read_csv(file.path(RAW, "prices.csv.gz"), show_col_types = FALSE)
spy    <- read_csv(file.path(RAW, "spy.csv.gz"), show_col_types = FALSE) |>
  arrange(date) |>
  transmute(date, spy = adjusted, spy_ret = spy / lag(spy) - 1)

TEST_START  <- as.Date("2024-01-01")
VALID_START <- as.Date("2019-01-01")
GAME_START  <- as.Date("2026-08-26")
GAME_END    <- as.Date("2026-10-30")
COST_BPS    <- 10   # one-way trading cost, basis points

FEATURES <- c("mom_12_1", "mom_6_1", "rev_1m", "rev_1w", "vol_1m", "vol_6m",
              "beta_1y", "dist_high", "rel_volume")

# Daily features, using only data up to and including each day's close -----
daily <- prices |>
  arrange(symbol, date) |>
  left_join(spy, by = "date") |>
  group_by(symbol) |>
  mutate(
    ret        = adjusted / lag(adjusted) - 1,
    mom_12_1   = lag(adjusted, 21) / lag(adjusted, 252) - 1,
    mom_6_1    = lag(adjusted, 21) / lag(adjusted, 126) - 1,
    rev_1m     = adjusted / lag(adjusted, 21) - 1,
    rev_1w     = adjusted / lag(adjusted, 5) - 1,
    vol_1m     = slide_dbl(ret, sd, .before = 20, .complete = TRUE),
    vol_6m     = slide_dbl(ret, sd, .before = 125, .complete = TRUE),
    beta_1y    = slide2_dbl(ret, spy_ret, ~ cov(.x, .y) / var(.y),
                            .before = 251, .complete = TRUE),
    dist_high  = adjusted / slide_dbl(adjusted, max, .before = 251, .complete = TRUE) - 1,
    rel_volume = log(slide_dbl(volume, mean, .before = 20, .complete = TRUE) /
                     slide_dbl(volume, mean, .before = 251, .complete = TRUE)),
    # Same holding window as the class model: close of t+1 to close of t+20.
    target_raw  = lead(adjusted, 20) / lead(adjusted, 1) - 1,
    target_end  = lead(date, 20)
  ) |>
  ungroup()

# Monthly panel: first trading day of each month, plus the game start date.
form_dates <- spy |>
  mutate(month = floor_date(date, "month")) |>
  group_by(month) |> summarise(date = min(date), .groups = "drop") |>
  pull(date)
game_signal_date <- max(spy$date[spy$date < GAME_START])   # close of 25 Aug

rank01 <- function(x) (rank(x, na.last = "keep") - 1) / (sum(!is.na(x)) - 1)

panel <- daily |>
  filter(date %in% c(form_dates, game_signal_date)) |>
  drop_na(all_of(FEATURES)) |>
  group_by(date) |>
  mutate(across(all_of(FEATURES), rank01),
         target_rel = target_raw - mean(target_raw, na.rm = TRUE)) |>
  ungroup()

# Model helpers -------------------------------------------------------------
fit_xgb <- function(train, p, seed = 6400) {
  dtrain <- xgb.DMatrix(as.matrix(train[FEATURES]), label = train$target_rel)
  xgb.train(params = xgb.params(objective = "reg:squarederror",
                                max_depth = p$max_depth,
                                learning_rate = p$learning_rate,
                                min_child_weight = p$min_child_weight,
                                subsample = 0.8, colsample_bytree = 0.8,
                                nthread = 1, seed = seed),
            data = dtrain, nrounds = p$nrounds, verbose = 0)
}

# Predict month t with a model trained on every row whose target had ended
# before t: an expanding window with an automatic one-month embargo.
walk_forward <- function(dates, p, seed = 6400) {
  map_dfr(dates, function(t) {
    train <- panel |> filter(date < t, target_end < t, !is.na(target_rel))
    test  <- panel |> filter(date == t)
    m <- fit_xgb(train, p, seed)
    test |> mutate(.pred = predict(m, as.matrix(test[FEATURES])))
  })
}

rank_ic <- function(preds) {
  preds |> filter(!is.na(target_raw)) |>
    group_by(date) |>
    summarise(ic = cor(.pred, target_raw, method = "spearman"), .groups = "drop")
}

# Tuning on 2019-2023 only ----------------------------------------------------
# Refit once a year here to keep the grid search cheap.
grid <- expand_grid(max_depth = c(2, 3, 4), learning_rate = c(0.02, 0.05),
                    nrounds = c(100, 300), min_child_weight = c(5, 20))

valid_dates <- form_dates[form_dates >= VALID_START & form_dates < TEST_START]

tune <- grid |>
  mutate(ic = pmap_dbl(list(max_depth, learning_rate, nrounds, min_child_weight),
    function(max_depth, learning_rate, nrounds, min_child_weight) {
      p <- list(max_depth = max_depth, learning_rate = learning_rate,
                nrounds = nrounds, min_child_weight = min_child_weight)
      preds <- map_dfr(split(valid_dates, year(valid_dates)), function(ds) {
        t0 <- min(ds)
        m <- fit_xgb(panel |> filter(date < t0, target_end < t0, !is.na(target_rel)), p)
        test <- panel |> filter(date %in% ds)
        test |> mutate(.pred = predict(m, as.matrix(test[FEATURES])))
      })
      mean(rank_ic(preds)$ic)
    })) |>
  arrange(desc(ic))

best <- as.list(tune[1, c("max_depth", "learning_rate", "nrounds", "min_child_weight")])
write_csv(tune, file.path(DERIVED, "improved_tuning.csv"))

# Out-of-sample test: same 34 formation dates as the class backtest -------------
original_dates <- read_csv(file.path(DERIVED, "original_backtest_monthly.csv"),
                           show_col_types = FALSE)$date
test_preds <- walk_forward(original_dates, best)
write_csv(test_preds |> select(date, symbol, .pred, target_raw, target_rel),
          file.path(DERIVED, "improved_monthly_preds.csv"))

# Portfolios on the same dates -------------------------------------------------
top10 <- function(preds, score) {
  preds |> group_by(date) |> slice_max({{ score }}, n = 10, with_ties = FALSE) |>
    ungroup() |> select(date, symbol, target_raw)
}

turnover <- function(holdings) {
  h <- split(holdings$symbol, holdings$date)
  c(1, map2_dbl(h[-length(h)], h[-1], ~ 1 - length(intersect(.x, .y)) / 10))
}

port_returns <- function(holdings, label) {
  holdings |> group_by(date) |> summarise(gross = mean(target_raw), .groups = "drop") |>
    mutate(turnover = turnover(holdings),
           net = gross - 2 * turnover * COST_BPS / 1e4,
           strategy = label)
}

panel_test <- panel |> filter(date %in% original_dates)
orig_preds <- read_csv(file.path(DERIVED, "original_monthly_preds.csv"), show_col_types = FALSE) |>
  rename(target_raw = target)

strategies <- bind_rows(
  port_returns(top10(orig_preds, .pred), "class model"),
  port_returns(top10(test_preds, .pred), "improved model"),
  port_returns(top10(panel_test, mom_12_1), "12-1 momentum, top 10"),
  panel_test |> group_by(date) |> summarise(gross = mean(target_raw), .groups = "drop") |>
    mutate(turnover = 0, net = gross, strategy = "equal-weight universe")
)

spy_aligned <- spy |>
  transmute(date, spy_target = lead(spy, 20) / lead(spy, 1) - 1)
strategies <- strategies |>
  bind_rows(spy_aligned |> filter(date %in% original_dates) |>
              transmute(date, gross = spy_target, turnover = 0, net = gross, strategy = "SPY")) |>
  left_join(spy_aligned, by = "date")
write_csv(strategies, file.path(DERIVED, "strategy_returns.csv"))

# Summary table ----------------------------------------------------------------
ew <- strategies |> filter(strategy == "equal-weight universe") |> select(date, ew = gross)

summary_tbl <- strategies |>
  left_join(ew, by = "date") |>
  group_by(strategy) |>
  summarise(
    months        = n(),
    cum_return    = prod(1 + net) - 1,
    sharpe        = mean(net) / sd(net) * sqrt(12),
    alpha_spy     = if (sd(net - spy_target) > 0) coef(lm(net ~ spy_target))[[1]] * 12 else 0,
    alpha_spy_t   = if (sd(net - spy_target) > 0) summary(lm(net ~ spy_target))$coefficients[1, 3] else NA,
    beta_spy      = if (sd(net - spy_target) > 0) coef(lm(net ~ spy_target))[[2]] else 1,
    max_drawdown  = min(cumprod(1 + net) / cummax(cumprod(1 + net)) - 1),
    alpha_ew      = if (sd(net - ew) > 0) coef(lm(net ~ ew))[[1]] * 12 else 0,
    alpha_ew_t    = if (sd(net - ew) > 0) summary(lm(net ~ ew))$coefficients[1, 3] else NA,
    avg_turnover  = mean(turnover[-1]),
    .groups = "drop")

# Predictive performance, all on one basis --------------------------------------
# Forecasts and outcomes are both measured relative to the month's cross-
# sectional average, so a model that forecasts raw returns and one that
# forecasts relative returns are scored the same way.
predictive <- function(preds, label) {
  b <- preds |> filter(!is.na(target_raw)) |> group_by(date) |>
    mutate(pred_rel = .pred - mean(.pred), y_rel = target_raw - mean(target_raw)) |>
    ungroup()
  monthly <- b |> group_by(date) |>
    summarise(ic     = cor(.pred, target_raw, method = "spearman"),
              top    = mean(target_raw[rank(-.pred, ties.method = "first") <= 10]),
              bottom = mean(target_raw[rank(.pred, ties.method = "first") <= 10]),
              ew     = mean(target_raw), .groups = "drop") |>
    mutate(spread = top - bottom, model = label)
  tstat <- function(x) mean(x) / sd(x) * sqrt(length(x))
  list(monthly = monthly,
       summary = tibble(model = label,
                        mean_ic = mean(monthly$ic), ic_t = tstat(monthly$ic),
                        r2 = 1 - sum((b$y_rel - b$pred_rel)^2) / sum(b$y_rel^2),
                        spread = mean(monthly$spread), spread_t = tstat(monthly$spread),
                        beat_ew = mean(monthly$top > monthly$ew)))
}

nolevels_preds <- read_csv(file.path(DERIVED, "original_nolevels_monthly_preds.csv"),
                           show_col_types = FALSE) |> rename(target_raw = target)

pred_all <- list(
  predictive(orig_preds, "class model"),
  predictive(nolevels_preds, "class model without price levels"),
  predictive(test_preds, "improved model"),
  # The simple benchmark as a forecast: rank on 12-1 momentum, nothing fitted.
  # A rank is not a return forecast, so its R^2 is not defined.
  predictive(panel_test |> mutate(.pred = mom_12_1), "12-1 momentum")
)
ic_summary <- map_dfr(pred_all, "summary") |>
  mutate(r2 = if_else(model == "12-1 momentum", NA_real_, r2))
write_csv(map_dfr(pred_all, "monthly"), file.path(DERIVED, "predictive_monthly.csv"))

# Seed robustness: the model subsamples rows and columns, so refit the whole
# walk-forward test with ten different seeds.
seed_runs <- map_dfr(1:10, function(sd_) {
  pr <- walk_forward(original_dates, best, seed = sd_)
  ret <- port_returns(top10(pr, .pred), "improved")
  predictive(pr, "improved")$summary |>
    mutate(seed = sd_, cum_return = prod(1 + ret$net) - 1,
           sharpe = mean(ret$net) / sd(ret$net) * sqrt(12))
})
write_csv(seed_runs, file.path(DERIVED, "seed_robustness.csv"))

# The game window -------------------------------------------------------------
game_preds <- walk_forward(game_signal_date, best)
game_pick  <- game_preds |> slice_max(.pred, n = 10, with_ties = FALSE)
px <- prices |> filter(date %in% c(GAME_START, GAME_END)) |>
  select(symbol, date, adjusted) |> pivot_wider(names_from = date, values_from = adjusted)
px$ret <- px[[as.character(GAME_END)]] / px[[as.character(GAME_START)]] - 1
game_improved <- tibble(portfolio = "improved model (signal 25 Aug)",
                        return = mean(px$ret[match(game_pick$symbol, px$symbol)]),
                        tickers = paste(game_pick$symbol, collapse = " "))
write_csv(game_improved, file.path(DERIVED, "game_improved.csv"))

write_csv(summary_tbl, file.path(DERIVED, "strategy_summary.csv"))
write_csv(ic_summary, file.path(DERIVED, "ic_summary.csv"))

cat("best hyperparameters:", paste(names(best), unlist(best), sep = "=", collapse = ", "), "\n")
print(head(tune, 5))
print(summary_tbl, width = Inf)
print(ic_summary)
print(seed_runs |> select(seed, mean_ic, spread, spread_t, cum_return, sharpe), n = 10)
print(game_improved)
