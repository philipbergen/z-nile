---
title: A recorded confirmation names what it covered and goes when that changes
when: design
tags: [confirmation, approval, record]
check: Can the thing a recorded confirmation or approval covers change after it was given without the confirmation going, and which command, land or claim refuses a confirmation that no longer matches? And does every file under the issue's `acceptance/` that `check.sh` runs and that is not a `*.spec.luau` (a `narrow.py`, a `.sh` helper) reach the approval hash through a digest written in `check.sh`?
---
A line that says "the user confirmed" is true only of the text the user saw. If the record or the idea can grow after the line, the line vouches for words nobody confirmed.

**Why:** c0260 design review 009 F4: a message recorded after the last round, or a hand edit of the Problem after `--confirm`, left the `Confirmed` line standing, and the claim and the audit accepted it.

**How to apply:** each round records what it was given (counts of the user's messages and questions, a hash of the idea) where the engine writes it; the confirmation is refused when that no longer matches, and a record or a round after it drops the line. Check it where the item is still an unclaimed capture, so later design edits do not void it.

**Also:** c0288 design review 001 F5: an approval hashes `check.sh` and `*.spec.luau`, not a shell helper under `acceptance/`. A value the human approves (a floor, a blob) therefore goes in `check.sh` as an argument, and the helper keeps only logic.

**Also:** c0397 design review 001 F1: c0397's AC1 was judged wholly by `acceptance/narrow.py`, and its folder held no `*.spec.luau`, so the approval contract covered nothing of AC1: a narrow.py swapped for `sys.exit(0)` after `./zn approve` passed `ready` and `done`. The fix pins the helper's sha256 in `check.sh`, inside `check`, failing closed, so an edit of the helper needs an edit of `check.sh`, which the approval hashes.
