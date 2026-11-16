---
title: Facts judged together are read at one moment
when: both
tags: [races, files, locks]
check: Where a decision reads two facts that must belong together (a pid and its start id, an owner and its token), are they in one file written whole (written to a temp file, then renamed), or is the first one re-read to confirm nothing changed in between?
---
Two files read milliseconds apart can come from two different writers: the folder changes hands between the reads, and the decision pairs one writer's pid with another's id.

**Why:** R0047 design review 004 F2: the takeover's owner was judged from `takeover/pid` and `takeover/start`, read separately; if the takeover changed hands between the reads, a live owner looked reused and its takeover was removed, a race the old rule (pid only) didn't have.

**How to apply:** write the pair as one line in one file, through a temp file and a rename, and parse both from that one read; or re-read the first file after the second and judge only if it is unchanged. The same goes for any single value a reader can catch half written: write it whole.

c0180 design review 005 F1: a runner read a tree's state before and after a run and combined the two reads, but every case set the state before the run started, so a runner reading it only before, or only after, passed them all. A rule that reads one fact twice around a run needs a case where the fact changes during the run, in each direction.

**Note** (c0265 design review 022 F3): a command that fetches into refs every checkout shares (`refs/remotes/origin/*`, a fetched `refs/zn/*` namespace) retries a sibling worktree's ref lock once, and resolves `origin/main` once to a sha that every later step of the attempt names (tree, parent, claimed set), as `publish.commit` does. Check: does this command fetch into a shared ref, and does it read the same shared ref twice in one decision?
