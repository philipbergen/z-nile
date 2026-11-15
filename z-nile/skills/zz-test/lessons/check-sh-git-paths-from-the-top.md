---
title: Git pathspecs in a check.sh are read from the project home it runs in
when: design
tags: [check-sh, git, paths]
check: Does every `git grep`, `git log -- <path>` or `git ls-tree` in a check.sh name its paths from the repository's top (`:(top)` pathspecs, `--full-name` output, absolute paths), since `ac.sh` cds to the item's project home first?
---
`ac.sh` runs a check.sh from the item's project home (`z-nile/` for z-nile's items), and git reads pathspecs relative to the current folder, so `':(glob)*/.tracker/**'` there means `z-nile/*/.tracker/**` and matches nothing: the check passes for the wrong reason.

**Why:** c0278 prep (its revision after design review 001): AC11's "no live item on origin/main depends on c0268" grep, tried for c0266 (which d0298 depends on), found nothing until it used `--full-name` and `':(top,glob)*/.tracker/**'`.

**How to apply:** use `:(top…)` pathspecs and `--full-name`, and try each such line on a case that must hit (a known dependent) before relying on its silence.
