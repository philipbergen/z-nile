---
title: Resolve a merge's conflicts before rerunning the scripts that rewrite those files
when: build
tags: [merge, scripts, conflicts]
check: Does `git diff --name-only --diff-filter=U` print nothing before I rerun a script that rewrites tracked files (a rename, a rewrite, a formatter)?
---
A script that rewrites files reads whatever is on disk. Run during a merge, it rewrites the conflicted copy, markers and both sides included, and reports success: the counts look right, and the resolution that follows (taking one side) throws its work away or keeps half of it.

**Why:** c0115's rebase onto landed c0120, twice: after merging the prep into the implementation, `rename-lesson-ids` ran while `harvest.md` was still conflicted. It rewrote ids on both sides of the markers and reported them as done; the file was then resolved by taking the prep's side, and the rename had to run again.

**How to apply:** after a merge, resolve every conflict (`git diff --name-only --diff-filter=U` prints nothing), then run the scripts the protocol reruns after a merge, then commit. Prefer scripts that refuse a file with conflict markers.
