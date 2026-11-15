---
title: Deleted files are read from a diff that pairs no renames
when: both
tags: [git, diff, deletions]
check: When code reads which files a range deleted, does it ask git for them with `--no-renames --diff-filter=D`, rather than take them from a `--name-only` list, where a deleted file that resembles an added one is a rename and only the new path appears?
---
`git diff --name-only <a> <b>` detects renames by default: a deleted file whose text is close to a file added in the same range is reported as a rename, and `--name-only` prints only the new path. The deletion is not in the list at all.

**Why:** c0301's prep: `land.spec` deleted `gone.spec.luau` in one layer while another layer added the similar `alpha.spec.luau`. The trace's adapter took the deleted specs from `diffList` and found none, so a deleted spec could not be cited. The fixture's two specs differed in one word, and real specs share boilerplate just as closely.

**How to apply:** list the deletions with their own call (`git diff --name-only --no-renames --diff-filter=D <a> <b>`), and keep any list a rule already relies on (sources, the files a stack changed) as it is. `git diff-tree` per commit pairs no renames unless asked, so a commit's file list is safe.
