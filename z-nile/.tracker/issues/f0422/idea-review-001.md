# Idea review 001

## Findings

- F1: The membership rule covers only open tickets, but a tributary groups rafts and raftless tickets, and the board counts done items. So nothing says which tributary a ticket in a raft belongs to (its own or its raft's), whether a raft in no tributary or in two is an error, or which tributary a done item counts toward. "How many of its items are done" can't be checked true or false.
- F2: The fence "does not change how dependencies or workability are computed" doesn't hold. Problem 2 says the board computes dependencies and workability for rafts. The bands, though, also place raftless tickets, need a new "steps of distance from workable" value and a new "how many it unblocks" count. "Unblocks" doesn't say whether it counts only direct dependents or every item downstream, so neither the sort nor the card count can be checked.
- F3: The fence "does not build or change the worker loop, which is f0420's" contradicts two Solution lines. `z-work <tributary>` adds a new way to pick work and a new stop rule to the worker. And `./zn work <raft>` printing the dependency graph is already in f0420's scope decision of 2026-11-20 ("it shows the dependency graph"), so this idea overlaps f0420's own scope.
- F4: The solution isn't the smallest. No Problem line needs three of its parts: highlighting upstream and downstream when a card is selected, the focused one-raft graph with lines, or the text graph from `./zn work <raft>`. Problem 2 only asks what can be worked now, and the workable band answers that.

## Verdict

revise
