# 02_original.R ----------------------------------------------------------
# Reproduce the class XGBoost model exactly, with Sys.Date() replaced by an
# explicit as-of date, and evaluate it three ways:
#   1. the out-of-sample backtest as coded, and with the annualization fixed;
#   2. the portfolio it recommended on the morning the stock game began;
#   3. how much that recommendation depends on the day the code is run.
# Reads data/raw/, writes data/derived/.

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(tidymodels)
  library(slider)
  library(xgboost)
})

POST    <- here("blog", "posts", "post9")
RAW     <- file.path(POST, "data", "raw")
DERIVED <- file.path(POST, "data", "derived")
dir.create(DERIVED, recursive = TRUE, showWarnings = FALSE)

prices_all <- read_csv(file.path(RAW, "prices.csv.gz"), show_col_types = FALSE)
spy_all    <- read_csv(file.path(RAW, "spy.csv.gz"), show_col_types = FALSE)

GAME_START <- as.Date("2026-08-26")   # first day of the class stock game
GAME_END   <- as.Date("2026-10-30")   # last trading day before 1 November

# The class code, verbatim except for the as-of date ------------------------
# tq_get(from = "2022-01-01", to = Sys.Date()) returns data strictly before
# the run date, so filtering date < as_of reproduces a run on that morning.
run_original <- function(as_of, drop_levels = FALSE) {
  prices <- prices_all |> filter(date >= as.Date("2022-01-01"), date < as_of)
  spy <- spy_all |>
    filter(date >= as.Date("2022-01-01"), date < as_of) |>
    select(date, spy_price = adjusted) |>
    mutate(spy_ret = spy_price / dplyr::lag(spy_price) - 1)

  df <- prices |>
    group_by(symbol) |> arrange(date) |>
    mutate(return = adjusted / dplyr::lag(adjusted) - 1) |>
    ungroup() |>
    left_join(spy |> select(date, spy_ret), by = "date") |>
    group_by(symbol) |>
    mutate(
      mom_1m = dplyr::lag(adjusted, 21) / dplyr::lag(adjusted, 1) - 1,
      mom_3m = dplyr::lag(adjusted, 63) / dplyr::lag(adjusted, 1) - 1,
      mom_6m = dplyr::lag(adjusted, 126) / dplyr::lag(adjusted, 1) - 1,
      vol_1m = slide_dbl(dplyr::lag(return), sd, .before = 21, .complete = TRUE),
      ret_5d = dplyr::lag(adjusted, 5) / dplyr::lag(adjusted, 1) - 1,
      excess_ret = return - spy_ret
    ) |>
    ungroup() |>
    drop_na()

  df <- df |>
    group_by(symbol) |>
    mutate(target = dplyr::lead(adjusted, 20) / dplyr::lead(adjusted, 1) - 1) |>
    ungroup() |>
    drop_na()

  train <- df |> filter(date < "2024-01-01")
  test  <- df |> filter(date >= "2024-01-01")

  rec <- recipe(target ~ ., data = train) |>
    update_role(date, symbol, new_role = "id")
  # Variant used only as a diagnostic: the same model without the raw price
  # and volume columns that tq_get() returns and `target ~ .` sweeps in.
  if (drop_levels) {
    rec <- rec |> step_rm(open, high, low, close, adjusted, volume)
  }

  xgb_spec <- boost_tree(trees = 300, tree_depth = 5, learn_rate = 0.05,
                         loss_reduction = 0, min_n = 10) |>
    set_engine("xgboost") |> set_mode("regression")

  set.seed(123)
  fit <- fit(workflow() |> add_recipe(rec) |> add_model(xgb_spec), data = train)

  preds <- predict(fit, test) |> bind_cols(test)

  weight_top10 <- function(d) {
    d |> arrange(desc(.pred)) |> slice(1:10) |>
      mutate(pred_positive = pmax(.pred, 0),
             weight = ifelse(sum(pred_positive) == 0, 1 / n(),
                             pred_positive / sum(pred_positive)))
  }

  latest_date <- max(preds$date)
  portfolio <- preds |> filter(date == latest_date) |> weight_top10()

  backtest <- preds |>
    mutate(month = floor_date(date, "month")) |>
    group_by(month) |> filter(date == min(date)) |>
    weight_top10() |> ungroup()

  # As coded, ifelse() with a length-one condition recycles the top stock's
  # weight to all ten, so weights sum to more than one: implicit leverage.
  # portfolio_return keeps that; portfolio_return_norm rescales to sum to one.
  returns <- backtest |>
    group_by(month, date) |>
    summarise(portfolio_return = sum(weight * target, na.rm = TRUE),
              weight_sum = sum(weight),
              portfolio_return_norm = sum(weight / sum(weight) * target, na.rm = TRUE),
              .groups = "drop")

  # SPY over the same window as the target: close of t+1 to close of t+20.
  spy_aligned <- spy |>
    mutate(spy_target = dplyr::lead(spy_price, 20) / dplyr::lead(spy_price, 1) - 1) |>
    select(date, spy_target)

  spy_returns <- spy |>
    mutate(month = floor_date(date, "month")) |>
    group_by(month) |>
    summarise(spy_return = prod(1 + (spy_price / dplyr::lag(spy_price) - 1), na.rm = TRUE) - 1,
              .groups = "drop")

  monthly_preds <- preds |>
    mutate(month = floor_date(date, "month")) |>
    group_by(month) |> filter(date == min(date)) |> ungroup() |>
    select(date, symbol, .pred, target)

  list(as_of = as_of, latest_date = latest_date, monthly_preds = monthly_preds,
       predictors = fit |> extract_recipe() |> summary() |>
         filter(role == "predictor") |> pull(variable),
       portfolio = portfolio |> select(symbol, .pred, weight),
       returns = returns |> left_join(spy_returns, by = "month") |>
         left_join(spy_aligned, by = "date"))
}

# 1. Backtest as of the data end -------------------------------------------
full <- run_original(as.Date("2026-11-14"))
r <- full$returns

capm <- lm(portfolio_return ~ spy_return, data = r)
capm_fixed <- lm(portfolio_return_norm ~ spy_target, data = r)
original_metrics <- tibble(
  months          = nrow(r),
  mean_weight_sum = mean(r$weight_sum),
  sharpe_fixed    = mean(r$portfolio_return_norm) / sd(r$portfolio_return_norm) * sqrt(12),
  alpha_fixed     = coef(capm_fixed)[[1]] * 12,
  alpha_fixed_t   = summary(capm_fixed)$coefficients[1, 3],
  beta_fixed      = coef(capm_fixed)[[2]],
  sharpe_as_coded = mean(r$portfolio_return) / sd(r$portfolio_return) * sqrt(252),
  sharpe_correct  = mean(r$portfolio_return) / sd(r$portfolio_return) * sqrt(12),
  alpha_as_coded  = coef(capm)[[1]] * 252,
  alpha_correct   = coef(capm)[[1]] * 12,
  alpha_t         = summary(capm)$coefficients[1, 3],
  beta            = coef(capm)[[2]],
  last_signal_date = full$latest_date,
  predictors      = paste(full$predictors, collapse = " ")
)

write_csv(r, file.path(DERIVED, "original_backtest_monthly.csv"))
write_csv(full$monthly_preds, file.path(DERIVED, "original_monthly_preds.csv"))

no_levels <- run_original(as.Date("2026-11-14"), drop_levels = TRUE)
write_csv(no_levels$returns, file.path(DERIVED, "original_nolevels_backtest_monthly.csv"))
write_csv(no_levels$monthly_preds, file.path(DERIVED, "original_nolevels_monthly_preds.csv"))
write_csv(original_metrics, file.path(DERIVED, "original_metrics.csv"))

# 2. The recommendation on the morning the game began -----------------------
hold_return <- function(symbols, weights, from = GAME_START, to = GAME_END) {
  px <- prices_all |> filter(symbol %in% symbols, date %in% c(from, to)) |>
    select(symbol, date, adjusted) |>
    pivot_wider(names_from = date, values_from = adjusted)
  px$ret <- px[[as.character(to)]] / px[[as.character(from)]] - 1
  w <- weights / sum(weights)          # what $100,000 can actually buy
  sum(w[match(px$symbol, symbols)] * px$ret)
}

game <- run_original(GAME_START)
reco <- game$portfolio

universe <- unique(prices_all$symbol)
spy_px <- spy_all |> filter(date %in% c(GAME_START, GAME_END)) |> arrange(date)

game_benchmarks <- tibble(
  portfolio = c("model recommendation (run 26 Aug)", "SPY",
                "equal-weight 95-stock universe"),
  return = c(hold_return(reco$symbol, reco$weight),
             spy_px$adjusted[2] / spy_px$adjusted[1] - 1,
             hold_return(universe, rep(1 / length(universe), length(universe))))
)

write_csv(reco |> mutate(signal_date = game$latest_date),
          file.path(DERIVED, "game_recommendation.csv"))
write_csv(game_benchmarks, file.path(DERIVED, "game_benchmarks.csv"))

# 3. Same code, different run dates -----------------------------------------
run_dates <- seq(as.Date("2026-08-17"), as.Date("2026-09-04"), by = "day")
run_dates <- run_dates[!weekdays(run_dates) %in% c("Saturday", "Sunday")]

sensitivity <- map_dfr(run_dates, function(d) {
  out <- run_original(d)
  tibble(run_date = d, signal_date = out$latest_date,
         overlap_with_26aug = length(intersect(out$portfolio$symbol, reco$symbol)),
         game_return = hold_return(out$portfolio$symbol, out$portfolio$weight),
         tickers = paste(out$portfolio$symbol, collapse = " "))
})
write_csv(sensitivity, file.path(DERIVED, "run_date_sensitivity.csv"))

print(original_metrics |> select(-predictors), width = Inf)
cat("\npredictors:", original_metrics$predictors, "\n\n")
print(reco)
print(game_benchmarks)
print(sensitivity |> select(-tickers))
