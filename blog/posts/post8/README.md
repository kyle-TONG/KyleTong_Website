# Post 8: Simulation, bootstrap intervals and hypothesis tests

Source for [What a confidence interval promises](index.qmd), published 2 November 2026.
The post uses one simulated population of hourly wages to show how a bootstrap confidence
interval is built, what its coverage means, how a null distribution gives a rejection region
and a p-value, and how sample size decides power.

## Files

```
post8/
├── index.qmd   the post: R chunks (knitr) and Observable JS chunks
└── README.md
```

There is no data directory. Everything is simulated inside the post.

## How it is built

The static parts are R, run at render time with `set.seed(2026)`, so the numbers in the text
are reproducible:

- a population of 1,000,000 hourly wages drawn from a lognormal with median $25 and log
  standard deviation 0.6, so the true mean is $25 exp(0.18) = $29.93;
- one sample of 50, resampled 5,000 times with replacement, for the bootstrap distribution
  and a percentile 95 percent interval;
- 1,000 repetitions of the whole procedure, each with 1,000 bootstrap resamples, for the
  coverage rate;
- a job-training experiment with 50 workers per group and a true effect of $2 an hour, and
  10,000 simulated no-effect experiments for the null distribution, rejection region and
  p-value.

The two interactive charts are Observable JS (`{ojs}` cells), which Quarto supports
natively. They run in the reader's browser, so they work on a static GitHub Pages site with
no server. They draw from the same lognormal population with `d3.randomLogNormal` seeded by
`d3.randomLcg`:

- **Coverage**: sliders for sample size (5-200), confidence level (80-99 percent) and number
  of repeated samples (50-400); each sample's interval uses 400 bootstrap resamples.
- **Testing and power**: sliders for the true effect ($0-8), workers per group (10-2,000)
  and the significance level; 2,000 simulated no-effect experiments give the null
  distribution and critical values, 1,000 experiments with the true effect give power.

The JS libraries (Observable runtime, Inputs, Plot, d3) load from a CDN, so the interactive
charts need an internet connection, and opening the HTML file directly from disk will not
run them. Serve the site, or view it on GitHub Pages.

## Checks

Coverage at n = 50 is about 93-94 percent and rises toward 95 percent with sample size; at
n = 10 it is in the mid-80s. In the power chart, with the effect set to zero the rejection
rate is close to the significance level; at $2 and 50 workers per group power is about 7
percent; about 1,500 per group gives roughly 80 percent, in line with the normal
approximation (SD of wages about $19.70).

## Reproducing

```bash
quarto render blog/posts/post8/index.qmd
```

Needs R with `ggplot2` and `scales`. Render this post on its own rather than the whole
project.
