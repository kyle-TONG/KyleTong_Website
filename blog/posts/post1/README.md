# Post 1: Simpson's paradox

Source files for [The average that disagrees with all of its parts](index.qmd), published
12 September 2026. Berkeley's 1973 graduate admissions gap runs one way in the pooled
numbers and the other way inside most departments; the post works through why a pooled
rate is a weighted average and what the weights are doing.

## Files

```
post1/
├── index.qmd      the post
├── simpsons.jpg   illustration of the within-group and pooled slopes
└── README.md
```

There is no acquisition or cleaning step. The data ships with R.

## Data

`UCBAdmissions` from R's `datasets` package: a 2 x 2 x 6 contingency table of admission
outcome by gender for the six largest departments at UC Berkeley in 1973. It comes from
Bickel, Hammel and O'Connell (1975), "Sex Bias in Graduate Admissions: Data from Berkeley",
*Science* 187, 398-404.

No API key, download or network access is needed. `as.data.frame(UCBAdmissions)` in any R
session reproduces the starting point.

## Reproducing

Render from the project root:

```bash
quarto render blog/posts/post1/index.qmd
```

Needs `dplyr`, `tidyr`, `ggplot2`, `knitr` and `scales`.
