# 04_game.R --------------------------------------------------------------
# Summarize the class stock game: 45 teams, each running a $100,000
# intuition-based portfolio and a $100,000 portfolio built from the class
# model's recommendations, 26 August to 1 November 2026.
#
# The results file was shared on Canvas and stays in data/course/, which is
# gitignored. This script writes only anonymous derived returns.

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(readxl)
})

POST    <- here("blog", "posts", "post9")
DERIVED <- file.path(POST, "data", "derived")
START   <- 1e5

game <- read_excel(file.path(POST, "data", "course", "Full_Results.xlsx")) |>
  mutate(team = row_number(),
         intuition = portfolio1 / START - 1,
         model     = portfolio2 / START - 1,
         difference = model - intuition) |>
  select(team, intuition, model, difference)

stopifnot(nrow(game) == 45, !anyNA(game))

tt <- t.test(game$model, game$intuition, paired = TRUE)
set.seed(123)
boot <- replicate(10000, mean(sample(game$difference, replace = TRUE)))

stats <- tibble(
  teams          = nrow(game),
  mean_intuition = mean(game$intuition),
  mean_model     = mean(game$model),
  sd_intuition   = sd(game$intuition),
  sd_model       = sd(game$model),
  mean_diff      = mean(game$difference),
  share_model_better = mean(game$difference > 0),
  p_paired       = tt$p.value,
  boot_lo        = quantile(boot, 0.025),
  boot_hi        = quantile(boot, 0.975),
  correlation    = cor(game$intuition, game$model)
)

write_csv(game, file.path(DERIVED, "game_results.csv"))
write_csv(stats, file.path(DERIVED, "game_stats.csv"))
print(stats, width = Inf)
