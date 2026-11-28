# Idea review 002

## Findings

- F1: Solution 1 limits `./zn ready <issue-id>` to a ticket "whose `depends_on` have landed", and Solution 2 removes the rafting step, so a prepared ticket whose dependency is built but not landed is left with no stated path. Today that ticket is rafted and then readied with `./zn ready <R-id> --on <R-id>` (f0399; `work.baseFor` picks the base), which lets a worker build on a finished, unlanded raft without waiting for the owner's landing approval. The issue-id form refuses `--on` (`main.luau:6911`, "the light path (ready <issue>) takes no --on"), and neither the Solution nor the Non-goals says whether building on an unlanded dependency survives for a raftless ticket or is given up. A reader cannot tell which, and this ticket's own dependents (`f0465`, `c0466`) are exactly such chains.

## Verdict

revise
