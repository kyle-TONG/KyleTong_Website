# 03_analyze.R -----------------------------------------------------------
# Price production in the 2026-27 market and write the summary tables the
# post reports. Reads data/derived/analysis_data.csv, writes results/tables/.

source(here::here("blog", "posts", "post2", "R", "00_config.R"))

analysis <- read_csv(ANALYSIS_FILE, show_col_types = FALSE)

# The market's price of production -----------------------------------------
# A one-variable regression of salary on projected VORP. The slope is what a
# team paid, on average, for one win above replacement; the intercept is what
# it paid a player who produced nothing.
market_fit <- lm(salary ~ proj_vorp, data = analysis)

analysis <- analysis |>
  mutate(
    market_value = predict(market_fit),
    surplus      = (market_value - salary) / 1e6
  )

# Dollars per unit of production, by group. Positive VORP only: a negative
# denominator would make the ratio meaningless.
price_of_production <- function(df, ...) {
  df |>
    group_by(...) |>
    summarise(
      players       = n(),
      median_salary = median(salary_m),
      median_vorp   = median(proj_vorp),
      total_salary  = sum(salary),
      total_vorp    = sum(pmax(proj_vorp, 0)),
      .groups       = "drop"
    ) |>
    mutate(cost_per_vorp = total_salary / total_vorp / 1e6)
}

salary_tier <- function(x) {
  cut(x, breaks = c(0, 5, 15, 30, 50, Inf),
      labels = c("Under $5M", "$5-15M", "$15-30M", "$30-50M", "Over $50M"))
}

analysis <- analysis |> mutate(tier = salary_tier(salary_m))

by_tier     <- price_of_production(analysis, tier)
by_position <- price_of_production(analysis, pos_group)
by_age      <- price_of_production(analysis, age_band)

# Robustness: the same tables restricted to players who were available for
# most of the season, so the ratios are not driven by injured contracts.
healthy <- analysis |> filter(mp >= 1500)
by_tier_healthy     <- price_of_production(healthy, tier)
by_position_healthy <- price_of_production(healthy, pos_group)

# Availability, by tier. The tiers are not far apart, which is the point:
# missed time is not something only cheap players do.
availability <- analysis |>
  group_by(tier) |>
  summarise(players        = n(),
            median_games   = median(g),
            share_under_60 = mean(g < 60),
            .groups        = "drop")

surplus_leaders <- analysis |>
  arrange(desc(surplus)) |>
  transmute(player, age, pos, team, years_left,
            salary_m = round(salary_m, 1),
            proj_vorp = round(proj_vorp, 2),
            surplus  = round(surplus, 1))

fit_summary <- tibble(
  term      = names(coef(market_fit)),
  estimate  = unname(coef(market_fit)),
  std_error = unname(summary(market_fit)$coefficients[, 2]),
  r_squared = summary(market_fit)$r.squared,
  n         = nobs(market_fit)
)

write_csv(by_tier,             file.path(TABLE_DIR, "price_by_tier.csv"))
write_csv(by_tier_healthy,     file.path(TABLE_DIR, "price_by_tier_healthy.csv"))
write_csv(by_position,         file.path(TABLE_DIR, "price_by_position.csv"))
write_csv(by_position_healthy, file.path(TABLE_DIR, "price_by_position_healthy.csv"))
write_csv(by_age,              file.path(TABLE_DIR, "price_by_age.csv"))
write_csv(availability,        file.path(TABLE_DIR, "availability_by_tier.csv"))
write_csv(surplus_leaders,     file.path(TABLE_DIR, "surplus_leaders.csv"))
write_csv(fit_summary,         file.path(TABLE_DIR, "market_fit.csv"))

message(sprintf("league price of production: $%.1fM per VORP (n = %d, R2 = %.2f)",
                coef(market_fit)[["proj_vorp"]] / 1e6,
                nobs(market_fit), summary(market_fit)$r.squared))
print(by_tier)
print(by_position)
