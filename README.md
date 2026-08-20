# Omnomnomicon

Built output for [omnomnomicon.arkavian.house](https://omnomnomicon.arkavian.house).

**Do not edit anything here.** Every file in this repository is generated. The
site's source, its content, and its documentation live in a separate tree that is
never pushed, and a local `publish.sh` run replaces this repository's contents
with a fresh build.

GitHub Pages serves this repository from `main` at the root, with the source set
to "Deploy from a branch".

## Why the source is not here

The vault behind the site holds notes that are not published. A generator's
publish filter governs the built site only, so an unpublished note committed to a
public repository is public regardless. Keeping the source out entirely makes
that structural: nothing but the rendered output ever reaches GitHub, and no
credential exists that could read the vault.
