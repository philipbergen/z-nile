---
title: A finished check is never patched on a guess
when: both
tags: [sequestration, check-sh, emergent, guesses]
check: Does this layer change any `check.sh` or acceptance file outside the raft's own members (a finished item's, another raft's), and if so whose decision on record allows it: a user's ruling, or only your own guess?
---
A finished item's `check.sh` is sequestered like any other. When another raft lands mid-review and its finished check turns one of your specs red, the fix may well be one word in that file, but making it is not a build guess: zz-test allows an edit to a finished check only for a change the user decided, and otherwise says stop and escalate. An emergent issue does not change that; it only gives the edit an id.

**Why:** R0133 (2026-11-17): R0131 landed d0297 while R0133 was in review, and a failure message in d0297's `check.sh` (`z-nile/affected.luau has no usage line …`) made `c0120/finished` red, which stopped c0374's layer at the restack. The lead created emergent c0414, changed the word on the raft's first layer under its own guess G1, and went on. Final review 001 F2 (high): the content was right, the act was not the lead's to decide, and d0297's recorded approval hash for `check.sh` went stale.

**How to apply:** Stop the raft at the red, write the finding and the options under the raft's `## Open to the human` (keep the edit in the raft; merge it first as its own tracker pull request; fix it another way), and tell the person. Build nothing on the edit before the ruling. Guess mode covers choices the approved contract leaves open, not edits to another item's contract.

**Note (R0133 final-review-002 F2, 2026-11-18):** the ruling that lets a finished `check.sh` change must also say who re-records that item's approval: `approval.md` hashes the `check.sh`, and `approvedDrift` reads the finished items a later landing diff touches. Ask: after this edit, does the finished item's `approval.md` still hash its `check.sh`, and who re-records it?
