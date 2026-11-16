# Post 9: Predicting stock returns with gradient boosting

Source for [The stock model that looked too good](index.qmd), published 16 November 2026.
Revisits the class stock game (26 August to 1 November 2026), reproduces the class XGBoost
stock-selection model, diagnoses its backtest, and compares it out of sample with a rebuilt
gradient boosting model and simple benchmarks.

## Files

```
post9/
├── index.qmd                         the post; reads data/derived/ only
├── R/
│   ├── 01_acquire.R                  prices for the 95 stocks and SPY, 2012 to 13 Nov 2026
│   ├── 02_original.R                 class model reproduced; game recommendation; run-date test
│   ├── 03_improved.R                 rebuilt model, tuning, out-of-sample comparison
│   └── 04_game.R                     stock game summary
├── data/
│   ├── raw/                          Yahoo Finance prices (gitignored), coverage, metadata
│   ├── course/                       class results file (gitignored, not published)
│   └── derived/                      every number and chart in the post
└── README.md
```

Yahoo Finance's terms do not allow redistributing its data, so the two price files in
`data/raw/` are gitignored; `01_acquire.R` downloads them again. The class code and the game
results file were shared on Canvas. Neither is in this
repository: the results file sits in `data/course/`, which is gitignored, and only anonymous
per-team returns are committed (`data/derived/game_results.csv`). `02_original.R` contains
the class model logic, with `Sys.Date()` replaced by an explicit date.

## Reproducing

From the project root, in order:

```bash
Rscript blog/posts/post9/R/01_acquire.R
Rscript blog/posts/post9/R/02_original.R
Rscript blog/posts/post9/R/03_improved.R
Rscript blog/posts/post9/R/04_game.R
quarto render blog/posts/post9/index.qmd
```

`04_game.R` needs the class results file at `data/course/Full_Results.xlsx`. Needs
`tidyquant`, `tidyverse`, `tidymodels`, `slider`, `xgboost` (3.x API), `readxl`, `here`.
Render this post on its own, not the whole project.

## The class model, and what is wrong with it

Reproduced exactly: 95 stocks (the code's comment says 100), daily data from 2022, features
`mom_1m`, `mom_3m`, `mom_6m`, `vol_1m`, `ret_5d`, `excess_ret`, target the return from
t+1 to t+20, trained on 2022-2023, tested from January 2024, top ten stocks each month.

Problems found, each checked in `02_original.R`:

| Problem | Effect |
|---|---|
| Monthly returns annualized with √252 and ×252 | printed Sharpe 10.2 (correct 2.2), alpha 736% (correct 35%) |
| `ifelse()` with a length-one condition in the weights | every stock gets the top weight; weights sum to 1.81 on average |
| `recipe(target ~ .)` includes open, high, low, close, adjusted, volume | raw levels as predictors; Yahoo's are split-adjusted backward (NVDA shows $121 before its June 2024 10-for-1 split), so they carry future information. Removing them cuts mean rank IC from 0.057 (t 2.84) to 0.025 (t 1.09) |
| `drop_na()` after building a 20-day lead target | the newest 20 days are dropped, so "current" picks use month-old signals |
| SPY benchmark over calendar months | different window from the portfolio's t+1 to t+20 |
| Training labels in late 2023 end in January 2024 | small train/test overlap |
| Momentum computed as past over recent price | sign reversed; harmless for trees, misleading to read |

The game recommendation is the class code run with data through 25 August 2026, held from the
26 August close to the 30 October close with weights rescaled to sum to one.

## The improved model

- Features: 12-1 and 6-1 month momentum, 21-day and 5-day reversal, 21-day and 126-day
  volatility, 252-day beta to SPY, distance from the 252-day high, log of 21-day over 252-day
  average volume; each converted to a cross-sectional percentile every month.
- Target: return from t+1 to t+20 minus the cross-sectional mean.
- Sample: first trading day of each month, 2013 onward.
- Training: expanding window refit every month, only on rows whose target ended before the
  formation date.
- Tuning: 24-point grid (depth, learning rate, rounds, minimum child weight), chosen by mean
  rank IC on 2019-2023 with annual refits. Selected: depth 2, learning rate 0.02, 100 rounds,
  minimum child weight 5.
- Portfolio: top ten, equal weight; 10 basis points cost each way on traded weight.

Evaluation uses the same 34 formation dates as the class backtest (January 2024 to October
2026), and is split the way the assignment asks.

Predictive performance, with forecasts and outcomes both demeaned across stocks each month so
that a raw-return model and a relative-return model are scored alike: monthly rank IC and its
t-statistic, out-of-sample R² against forecasting no difference between stocks, and the
return of the top ten minus the bottom ten forecasts. The 12-1 momentum rank is scored the
same way as a no-fitting benchmark.

Investment performance, net of costs: total return, Sharpe (√12), beta to SPY over the
matching window, worst drawdown, alpha against the equal-weighted 95 stocks, and turnover,
for the class model, the improved model, a top-ten 12-1 momentum rule, the equal-weighted
universe and SPY.

Robustness: the improved model subsamples rows and columns, so the whole walk-forward test is
repeated with ten seeds (`seed_robustness.csv`). Total return ranges from 182% to 213% and
Sharpe from 1.33 to 1.43, so the conclusions do not hinge on one draw. With the price-level
columns removed, the class model's alpha against the equal-weighted universe falls from 15.1%
(t = 2.23) to 2.4% (t = 0.32).

## Limitations

The universe is today's large companies chosen in hindsight, which flatters every strategy
built on it; the equal-weighted universe benchmark controls for that only partly. Thirty-four
months is a short test. The game window is a single two-month draw. The class average for
model portfolios (+3.1%) is well above the rerun recommendation (−7.4%) and every nearby run
date; the results file does not record how teams implemented the picks.
