---
title: An exception that skips re-verification pins what it verified to what gets merged
when: design
tags: [merge, ci, guards]
check: Can the commit that gets merged differ from the one the check judged (a push after the check, another session's push), and does the merge itself refuse when it does?
---
A check that says "this head may merge without another CI run" is only as good as the link between the head it judged and the head that merges. `gh pr merge` takes whatever head the PR has at that moment.

**Why:** c0152 design review 001 F2: merge-check judged a sha the merger named, and step 4 merged the PR's current head; a fixup pushed after green would have merged untested.

**How to apply:** have the check print the exact sha, and merge with `--match-head-commit <sha>` (or the API's `sha`), so any later push voids the merge; say in the skill that the check is rerun after the next green CI.
