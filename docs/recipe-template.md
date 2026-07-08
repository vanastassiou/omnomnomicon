---
# HOW TO USE: copy this file into _recipes/ (optionally a subfolder) and rename
# it, e.g. `cp docs/recipe-template.md _recipes/banana-bread.md`. The filename
# without .md is the URL slug and must be unique across ALL recipe folders.
# Fill in the values and delete these comment lines.
layout: recipe
title: Recipe Title
date: 2026-01-01            # YYYY-MM-DD; orders the home feed
servings: 4                # a number
# Optional header + feed image. See the README "Images" section.
# image:
#   path: /assets/images/recipe-slug.jpg       # large image at the top of the page
#   thumbnail: /assets/images/recipe-slug.jpg  # small image in the home feed
#   caption: "Optional caption, Markdown allowed"
ingredients:
  - amount: 250            # a number
    unit: g                # one of: g, kg, ml, l, count
    name: flour
  - amount: 2
    unit: count            # 'count' = unitless (eggs, cloves); no unit word is shown
    name: eggs
---

Write the method here as Markdown.

1. First step.
2. Second step.
