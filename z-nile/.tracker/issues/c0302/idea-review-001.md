# Idea review 001

## Findings

- F1: The second Problem sentence is false as written. `--affected`, `./zn finish` (`z-nile/engine/main.luau:3779-3815`) and RC0 (`z-nile/templates/raft/check.sh:8`) choose specs by each spec's `watch.txt` (`z-nile/affected.luau:100-150`). So these three specs run in a raft's gate only when the raft changes a file in their watch lists (`zn`, `z-nile/engine/main.luau`, `z-nile/lib/sh.luau`, `z-nile/check.sh`, …). That means the gate goes red only for rafts that changed something those specs cover by the gate's own measure. A z-nile raft that touches only, say, `z-nile/engine/stack.luau` or a skill doc never runs them and stays green. So it isn't "every z-nile raft", and the "although the raft changed nothing those specs cover" clause contradicts how the gate picks them. A reader could check this and find it true: "any z-nile raft that changes a file those specs watch is red on its layer branch for a reason unrelated to its change."

## Verdict

revise
