---
# HOW TO USE: copy this file into _recipes/ (optionally a subfolder) and rename
# it, e.g. `cp docs/recipe-template.md _recipes/banana-bread.md`. The filename
# without .md is the URL slug and must be unique across ALL recipe folders.
# Fill in the values and delete these comment lines.
layout: recipe
title: Recipe Title
source:                               # REQUIRED before committing: fill this in.
                                      # A book, a URL, or any attribution. Examples:
                                      #   source: "Nigella Lawson, How to Eat, p.212"
                                      #   source: https://example.com/the-recipe
                                      #   source: "Family recipe, adapted"
                                      # Left empty on purpose: validation fails until sourced.
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

Write the method as Markdown. Keep each step to one primary action. For a
multi-phase recipe, group the steps under `### Phase name` subheadings
(numbering restarts under each); a short single-phase recipe can be one flat
numbered list.

### Phase name

1. First step.
2. Second step.

<!--
  Inline image example. Store the file under assets/images/ and reference it
  with a root-absolute path. Always write real alt text in the brackets.
  Delete this comment or replace it with a real image line:

  ![Batter in the loaf tin](/assets/images/recipe-slug-step.jpg)
-->

