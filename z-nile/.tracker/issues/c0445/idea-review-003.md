# Idea review 003

## Findings

- F1: Nothing says whether raft-plan's cap of about 1,500 changed lines applies to a merge the worker makes. The non-goals leave the cap alone, but `./zn recombine` with arguments skips the cap (z-raft skill, §1). So if the worker merges two adjacent feature rafts of 1,000 lines each, a reader can't tell whether that is allowed. A non-goal or Solution line should say plainly that the cap does, or does not, limit a worker's merge.

## Verdict

revise
