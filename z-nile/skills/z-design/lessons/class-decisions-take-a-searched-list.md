---
title: A decision that names a class is met by a searched list in one place, and a missing member refuses
when: design
tags: [decisions, exhaustive-lists, search]
check: Is the list the output of a pasted search, kept in one file, with a spec that fails on an unlisted hit? What does the check do when a listed member isn't there?
---
When the user decides a class ("run the gate stages that read tracker files"), a list written from memory meets only the members the author remembered, and the gap is exactly the wrong ok the decision exists to prevent.

**Why:** c0152 design review 002 F2: the trial ran audit and check-paths, a hand list of two; the reviewer's search found classified (slugs, check.sh listing) and others that judge main's new items with the PR. A subagent's second search then found more (repo-fence, both finished specs, board).

**How to apply:** paste the search into the Design and classify every hit, run or skip with a reason. Keep the result in one file the tool reads, with a spec that reruns the search and fails on a hit on neither list. Make a listed member missing from the tree a no, never a skip. Time the whole list, and say what it costs.
