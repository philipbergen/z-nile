---
title: Tracker-only changes are unreviewed by CI, not unread by it
when: design
tags: [ci, tracker-state, gate]
check: When a rule skips CI because the changes are in tracker files, which gate stages read those files (check-paths, finished, audit), and how is their interaction with the change being merged covered?
---
CI skips pushes that touch only tracker files, so a rule that lets a PR merge past "tracker-only" commits on main assumes those files can't affect the PR. But the gate reads them: check-paths scans every unfinished check.sh, audit judges every document, so a new check.sh naming a file the PR deletes makes the merged main red with nobody having run it.

**Why:** c0152 design review 001 F1: merge-check's first draft called the merge "the tree CI tested plus main's tracker changes"; the user decided to run check-paths and audit on the would-be merged tree first.

**How to apply:** list the gate stages that read the files the exception lets through, and run them on the merged tree (or narrow the exception) before skipping CI.
