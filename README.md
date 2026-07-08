# Omnomnomicon

A personal blog hosting two content types on GitHub Pages: dated journal
entries and structured recipes. Live at
[omnomnomicon.arkavian.house](https://omnomnomicon.arkavian.house).

## Stack

- Static site generator: Jekyll 3.10 via the `github-pages` gem (local build
  matches what GitHub Pages runs).
- Theme: [So Simple](https://github.com/mmistakes/so-simple-theme) via
  `remote_theme`.
- Ruby: 3.3.x (see `.ruby-version`), managed with Bundler into `vendor/bundle`.

## Prerequisites

1. Install Ruby 3.3.x. With Homebrew: `brew install ruby@3.3 && brew link --overwrite ruby@3.3`.
2. Verify the version: `ruby --version` should report `3.3.x`.

## Local development

1. Install gems into `vendor/bundle`:

   ```bash
   bundle config set --local path vendor/bundle
   bundle install
   ```

2. Serve the site with live reload:

   ```bash
   bundle exec jekyll serve
   ```

3. Open `http://127.0.0.1:4000`.

## Writing a journal entry

1. Create `_posts/YYYY-MM-DD-slug.md`.
2. Add front matter:

   ```yaml
   ---
   title: "Post title"
   date: 2026-01-01
   ---
   ```

3. Write the body in Markdown. The `post` layout applies automatically.

## Writing a recipe

1. Create `_recipes/slug.md`.
2. Add front matter following the schema:

   ```yaml
   ---
   layout: recipe
   title: Banana Bread
   date: 2026-01-02
   servings: 4
   ingredients:
     - amount: 250
       unit: g
       name: flour
     - amount: 3
       unit: count
       name: eggs
   ---
   Method goes in the body as Markdown.
   ```

3. Store amounts as structured `amount` + `unit` + `name`, never as prose.
4. Use only these units: `g`, `kg`, `ml`, `l`, `count`. `count` is for
   unitless items such as eggs and cloves.

## Validation

Recipe front matter is validated by `bin/validate_recipes.rb`:

- Locally, a pre-commit hook validates staged `_recipes/*.md`. It is wired via
  `git config core.hooksPath .githooks`, which a fresh clone must run once:

  ```bash
  git config core.hooksPath .githooks
  ```

- In CI, `.github/workflows/validate.yml` runs the same script on push and
  pull requests. The CI check is the non-skippable gate.

Run it manually against every recipe:

```bash
ruby bin/validate_recipes.rb _recipes/*.md
```

## Deployment

Pushing to `main` triggers a GitHub Pages build. Repository setup is one-time:

1. Set Pages source to the `main` branch (or GitHub Actions).
2. Set the custom domain to `omnomnomicon.arkavian.house`.
3. Add a DNS `CNAME` record: host `omnomnomicon` targets
   `vanastassiou.github.io`.
4. Enable "Enforce HTTPS" once the certificate provisions.

## Project documents

- `docs/architecture-decisions.md`: the durable record of why the stack is
  what it is.
- `plan.md`: the working plan, build order, and current status.
