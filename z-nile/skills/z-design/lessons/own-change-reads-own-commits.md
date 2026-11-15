---
title: What a branch changed is read from its own commits, not a diff from its merge base
when: design
tags: [merges, landing, git]
check: Where this design asks "did the branch change anything" or "does main already hold the branch's change", what does it read after the branch has merged a `main` that holds that change (`./zn sync`, a lost race's merge)? Does it read the branch's own non-merge commits that `main` lacks (`git log --no-merges <main>..HEAD`), not `git diff <merge-base> HEAD`, which reads nothing once the merge base has moved past them?
---
A branch's merge base with `main` moves forward every time the branch merges `main`. When `main` already holds the branch's change (an earlier land pushed it as a different commit, or someone made the same edit), merging it moves the merge base past the branch's own commit, and a diff from the merge base to HEAD is empty: the branch looks as if it never changed anything. A check built on that diff calls a landed branch "nothing to land" (or a finished branch "unchanged").

**Why:** c0258 design review 001 F2 (2026-11-15): `land`'s "already landed" test counted `git diff --name-only <merge-base HEAD origin/main> HEAD`. A git probe in which the branch merged the `main` holding its landed change read 0 own paths, so land still failed "nothing to land", the 2026-11-05 outcome the issue was filed for. The spec passed only because its branch never merged `main`.

**How to apply:** count the paths of `git log --no-merges --format= --name-only <main>..HEAD`, read before any merge, and say what a branch whose own commits cancel out reads as. Give the spec a case whose branch merged the `main` that holds its change before the command runs.
