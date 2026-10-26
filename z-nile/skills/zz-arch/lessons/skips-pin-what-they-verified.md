---
title: An exception that skips re-verification pins what it verified to what gets merged
when: design
tags: [merge, ci, guards]
check: Can the commit that gets merged differ from the one the check judged (a push after the check, another session's push), on either side of the merge (the head and the base tip), and does something refuse when it does? How long between the check's read of the base and the merge?
---
A check that says "this head may merge without another CI run" is only as good as the link between the head it judged and the head that merges. `gh pr merge` takes whatever head the PR has at that moment.

**Why:** c0152 design review 001 F2: merge-check judged a sha the merger named, and step 4 merged the PR's current head; a fixup pushed after green would have merged untested.

**How to apply:** have the check print the exact sha, and merge with `--match-head-commit <sha>` (or the API's `sha`), so any later push voids the merge; say in the skill that the check is rerun after the next green CI.

**Both sides (c0152 design review 003 F1):** `--match-head-commit` pins only the head; `gh pr merge --squash` lands on whatever main is when it runs, and a 2–3 minute trial widened that window from seconds to minutes while main moved every few minutes. Pin the base too: the check re-reads the tip after any slow step (and judges what arrived), prints the tip it judged, and the merger re-reads it with `git ls-remote` right before the merge and merges only when it is unchanged.

**Path-class skips (c0152 design review 004 F2):** a skip granted by path class ("only spend rows") also checks that the path still belongs to a live item in the merged tree, because a row written for a folder the PR moved away creates an orphan no path-overlap test sees. Check: can the skipped change land in a folder the other side removed?
