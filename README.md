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

1. Copy the stub: `cp docs/recipe-template.md _recipes/slug.md` (a subfolder is
   fine). The filename without `.md` is the URL slug and must be unique across
   all recipe folders.
2. Fill in the front matter following the schema:

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

Recipes may be organized into subfolders (for example
`_recipes/desserts/banana-bread.md`). Subfolders are for filing only: URLs are
flat (`/recipes/banana-bread/`), so every recipe basename must be unique across
all folders. The validator's `--all` mode enforces this.

## Images

Images are committed to the repository under `assets/images/` and served by
GitHub Pages. There is no external image host, which keeps the $0 constraint.

Do not use Git LFS: GitHub Pages does not serve LFS files, so an LFS-tracked
image would render as a broken link. Keep source images reasonably small
(resize before committing).

Three ways to use an image, all working for both journal posts and recipes:

1. Header image at the top of the page. Add to front matter:

   ```yaml
   image:
     path: /assets/images/banana-bread.jpg
     caption: "Optional caption, Markdown allowed"
   ```

2. Feed thumbnail on the home page. Add a `thumbnail` under `image`:

   ```yaml
   image:
     path: /assets/images/banana-bread.jpg
     thumbnail: /assets/images/banana-bread.jpg
   ```

3. Inline in the body, with standard Markdown:

   ```markdown
   ![Sliced banana bread](/assets/images/banana-bread-sliced.jpg)
   ```

Paths are absolute from the site root (`/assets/...`). This works because
`baseurl` is empty (ADR 10); the theme also passes front matter image paths
through `relative_url`, so they stay correct if `baseurl` ever changes.

## Validation

Recipe front matter is validated by `bin/validate_recipes.rb`:

- Locally, a pre-commit hook validates staged `_recipes/*.md`. It is wired via
  `git config core.hooksPath .githooks`, which a fresh clone must run once:

  ```bash
  git config core.hooksPath .githooks
  ```

- In CI, `.github/workflows/validate.yml` runs the same script on push and
  pull requests. The CI check is the non-skippable gate.

Run it manually against every recipe (recurses into subfolders):

```bash
ruby bin/validate_recipes.rb --all
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
