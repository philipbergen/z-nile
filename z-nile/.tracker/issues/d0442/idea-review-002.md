# Idea review 002

## Findings

- F1: The issue treats the code review as something each layer has, but it is one series per raft. zz-execute Phase 4 step 3 says the reviewer writes `review-NNN.md` "in the raft directory (starting at 001)". In that series NNN counts review rounds, not layers. `lightgit` and `rounds.KINDS` read the files the same way: they look for `review-NNN.md` in the raft's folder. So no file says which layer a review covered, and two Solution lines cannot be checked as written: "any of its layers has no `review-NNN.md` … names that layer" and "any layer's latest code review round … names that layer". The same framing also makes the first Problem sentence false. `./zn done` already refuses a raft that took the light path but is no longer light when the raft has no `review-NNN.md` (`main.luau:5501`). So it does read for code reviews, just not on the normal path. The fix is to say the rule per raft (the raft's folder holds no `review-NNN.md`, or its latest round is not settled) or to define how a review file is tied to a layer.

## Verdict

revise
