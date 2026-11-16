# Idea review 001

## Findings

- F1: The Solution's "or" branch can pass without fixing the Problem. It is met if zz-execute and zz-rules both name one route, and that route could be "open a pull request by hand", which is the very failure the Problem describes. It could also be the route zz-rules:135 already gives ("record it before the merge"), which zz-execute:91 contradicts ("After the merge… `./zn spend R0010 --phase deliver`"). A doc-only change that makes the two skills agree would count as done. But a deliver row recorded after `./zn done` would still sit on the local branch and still be lost when the worktree is removed, as #480's hand recovery of R0101's rows shows. So the first branch is something a reader can test against the Problem, and the second is not. Keep only the outcome where the row is on origin main with no hand-made pull request, or reword the second branch so it also guarantees the row reaches main.

## Verdict

revise
