# Idea review 001

## Findings

- F1: The first Solution sentence counts "every item that waits on it through depends_on" for a candidate raft, but depends_on only ever names issues; no `depends_on` in either tracker names an R-id. So a raft's count has no defined value, and a reader can't say whether a given count is true or false. It also doesn't say whether a member issue that waits on another member of the same raft counts toward that raft. Rafts stack dependencies inside themselves, and `ready` checks only the depends_on outside the raft. The sentence needs to state that a raft's count is the waiting items of its member issues, counted once each, and whether its own members count.

## Verdict

revise
