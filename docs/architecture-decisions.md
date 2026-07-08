# Architecture decision record

This document records the significant architectural decisions for the blog,
each with the context that forced it, the decision itself, the alternatives
rejected, and the consequences accepted. It is the durable record of *why*.
For the working build plan and current status, see `plan.md`.

Each decision has a status: Accepted, Superseded, or Deferred. Decisions are
numbered and append-only; to reverse one, add a new decision that supersedes
it rather than editing history.

## Format

Every entry states Context, Decision, Alternatives considered, and
Consequences. Context describes the constraint or problem. Decision states
what was chosen. Consequences record what the decision commits us to, good and
bad.

## ADR 1: Host on GitHub Pages

Status: Accepted

Context: The blog must cost $0 with no paid tiers and no service that has a
paid dependency. Day-to-day publishing should not require operating a server.

Decision: Host on GitHub Pages.

Alternatives considered: Netlify and Cloudflare Pages offer more build
flexibility but add a second account and a build pipeline outside GitHub.
Self-hosting fails the no-server and no-cost goals.

Consequences: Builds are constrained to the GitHub Pages environment,
including its whitelisted plugin set and its pinned Ruby and Jekyll versions.
No custom build step runs server-side. Any feature that is impossible on
GitHub Pages must be called out explicitly rather than worked around by
switching hosts.

## ADR 2: Jekyll as the static site generator

Status: Accepted

Context: GitHub Pages runs Jekyll natively without a separate build action, so
the generator choice interacts directly with ADR 1.

Decision: Use Jekyll, restricted to plugins whitelisted by GitHub Pages.

Alternatives considered: Hugo or Eleventy would require a GitHub Actions build
step to deploy to Pages, adding configuration and a failure surface. The
native path is simpler.

Consequences: No custom Ruby plugins run at build time. Any build-time logic
must be expressed in Liquid, front matter, or data files. This constraint
directly shapes ADR 8 (validation happens at commit, not through a plugin).

## ADR 3: So Simple theme via remote_theme

Status: Accepted

Context: The site needs a general blog theme that handles both dated posts and
a custom recipes collection, without vendoring theme files into the repository.

Decision: Use the So Simple theme through
`remote_theme: "mmistakes/so-simple-theme@3.2.0"`, pinned to a release.

Alternatives considered: Minimal Mistakes is heavier and carries more
configuration than this site needs. Recipe-only themes are rejected outright
because they do not handle journal posts. Minima plus a fully hand-written
theme would mean building navigation, feeds, and styling from scratch.

Consequences: The version is pinned because omitting it tracks the theme's
`master` branch and can break the build without warning. So Simple ships a
generic `collection` layout but no `recipe` layout, so a custom
`_layouts/recipe.html` is still required; it sets `layout: post` so Jekyll
layout inheritance wraps the recipe content in the theme's chrome.
Configuration uses So Simple's key set (`author` map, `locale`), not another
theme's.

## ADR 4: Two content collections

Status: Accepted

Context: The blog hosts two content types with different shapes. Journal
entries are prose. Recipes carry structured data.

Decision: Keep journal entries in the standard `_posts` collection and recipes
in a dedicated `_recipes` collection with `output: true` and its own layout.

Alternatives considered: A single collection with a `type` field would blur
the layouts and front matter defaults and complicate per-type validation.

Consequences: Each type gets its own layout defaults and permalink scheme.
Recipes have both their own `/recipes/` index and a presence in the shared
home feed (ADR 7).

## ADR 5: Structured ingredient data over prose

Status: Accepted

Context: Ingredients could be written as free prose or as structured data. The
choice determines whether later features can read amounts without re-parsing
old content.

Decision: Store each ingredient as separate `amount`, `unit`, and `name`
fields in front matter, never as prose.

Alternatives considered: Prose ingredients are faster to type but cannot be
scaled or reformatted programmatically without fragile parsing.

Consequences: Authoring a recipe means filling structured fields, enforced by
ADR 8. The structure is preserved even though nothing consumes the individual
fields yet. Recipe portion scaling is deferred, not rejected; the only reason
the structure exists now is so scaling can be added later without rewriting
existing recipes.

## ADR 6: Metric-only units, no conversion

Status: Accepted (supersedes an earlier draft that included imperial units)

Context: An earlier draft allowed a mixed vocabulary (`oz`, `lb`, `g`, `kg`,
`cup`, `count`) and reserved gram-multiplier constants for future
imperial-to-metric conversion.

Decision: Restrict the unit vocabulary to metric plus a unitless escape hatch:
`g`, `kg`, `ml`, `l`, `count`. Never perform unit conversion.

Alternatives considered: Supporting both measurement systems with conversion
would need per-ingredient density data for any volume-to-weight conversion
(`cup` to `g`), which is unwanted, and adds reader-facing JavaScript.

Consequences: There is nothing to convert, so no conversion code or density
data is ever needed. The vocabulary lives in one file, `_data/units.yml`, as
the single source of truth read by the validator (ADR 8). `count` is never
scaled by unit logic. Portion scaling, if added later, is pure multiplication
of `amount` with no unit math.

## ADR 7: Combined chronological home feed

Status: Accepted

Context: Recipes could appear only on their own index, or also surface in the
main feed alongside journal posts.

Decision: The home page shows a single chronological feed that merges posts
and recipes, newest first, in one column. Recipes also keep a separate
`/recipes/` index.

Alternatives considered: A separate index only is less code but hides recipes
from the main feed. A two-column desktop and interleaved mobile layout was
considered and rejected as more build effort than the value warranted.

Consequences: A custom `home` layout merges the collections with
`site.posts | concat: site.recipes | sort: "date" | reverse` and reuses the
theme's own entry include for consistent markup. No JavaScript and no
responsive column logic are involved.

## ADR 8: Commit-time validation over a CMS

Status: Accepted

Context: Structured recipe front matter (ADR 5) needs enforcement so malformed
recipes do not reach the site. GitHub Pages runs no custom plugin (ADR 2) and
the project wants no authentication backend.

Decision: Validate recipes with a Ruby script, `bin/validate_recipes.rb`, run
at two points: a committed pre-commit hook for fast local feedback, and a
GitHub Action that mirrors the same script as the authoritative gate.

Alternatives considered: A form-based CMS such as Decap would validate at input
time but requires an auth backend and pushes against the no-server, no-cost
goals. A build-time plugin is impossible under ADR 2.

Consequences: Validation happens at commit and push, not at input. The local
hook is skippable with `--no-verify` and never runs on GitHub web edits, so
the Action is the check that cannot be dodged. The hook is tracked in
`.githooks/` and activated with `git config core.hooksPath .githooks`, which a
fresh clone must run once. The script reads its allowed-unit vocabulary from
`_data/units.yml` so the rule lives in one place. It adds no new dependency
beyond the Ruby that Jekyll already requires.

## ADR 9: Ruby toolchain and gem management

Status: Accepted

Context: A working local build is required, matching the GitHub Pages
environment. The development machine has no passwordless sudo, but it does have
Homebrew.

Decision: Install Ruby 3.3 through Homebrew (`ruby@3.3`), pinned in
`.ruby-version`. Manage gems with Bundler into a repository-local
`vendor/bundle`. Depend on the `github-pages` meta-gem so the local gem set
matches production.

Alternatives considered: Installing Ruby through `apt` needs sudo, which is
password-gated here. Homebrew's default `ruby` formula is 4.0, on which the
GitHub Pages stack fails because Jekyll and Liquid call `Object#tainted?`,
removed in Ruby 3.2. Ruby 3.3 is what GitHub Pages runs and avoids that class
of breakage.

Consequences: Local builds equal production builds because the `github-pages`
gem pins the same Jekyll (3.10) and Liquid (4.0.4). Gems never require sudo
because they install under the repository. `vendor/` and `.bundle/` are
git-ignored. The CI workflow reads `.ruby-version` so the Ruby version has one
source of truth.

## ADR 10: Custom domain

Status: Accepted

Context: The site needs a stable URL, which sets `url` and `baseurl` in
`_config.yml` and determines the DNS records.

Decision: Serve from the subdomain `omnomnomicon.arkavian.house`.

Alternatives considered: A `USERNAME.github.io` user site or a project
subpath. The subdomain gives a clean root path (`baseurl` empty) and a
memorable name.

Consequences: `_config.yml` sets `url: "https://omnomnomicon.arkavian.house"`
and an empty `baseurl`. A `CNAME` file at the repository root holds the bare
domain. DNS needs a `CNAME` record for host `omnomnomicon` pointing at
`vanastassiou.github.io`. The GitHub repository's Pages settings set the custom
domain and enforce HTTPS once the certificate provisions.
