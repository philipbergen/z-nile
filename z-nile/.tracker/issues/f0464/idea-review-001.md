# Idea review 001

## Findings

- F1: The Problem sentence is false for the case it names: z-raft §4 runs the coherence review only on a raft of two or more issues, so a ticket delivered alone gets a rafting pull request and a raft document today but no coherence review, and a ticket that does get one is in a bundle, so it is not "delivered alone anyway".
- F2: Solution sentence 4 (each ticket on its own branch and pull request by default) is larger than the Problem: the Problem names only tickets that would be delivered alone anyway, while this sentence also ends `./zn raft-plan`'s default folding of defects and chores and its grouping of features that share a surface; sentences 1 to 3 already solve the stated Problem, and no Problem sentence says default bundling does harm.
- F3: Solution sentence 3 and the third non-goal leave a bundle made on request undecidable: either it still passes a rafting pull request and coherence review (then "No ticket needs" is false for its members), or it does not (then tightly coupled tickets lose the one review that checks their interfaces agree, and no non-goal says so).

## Verdict

revise
