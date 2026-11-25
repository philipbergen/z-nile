# Idea review 002

## Findings

- F1: Solution sentence 5's test refuses on the layers it is meant for. A restack rebases a layer only because its base moved, so the rebased local layer also holds the new base commits, and `git cherry origin/<layer> <layer>` marks those `+`. I ran this in a throwaway repository (layer pushed, main moved, layer rebased): it listed `+ main 1 (new base commit)` and `-` for both of the layer's own commits. With the layer below as the limit (`git cherry origin/layer2 layer2 main`) it listed only the two `-` lines.
- F2: Even when `--from-origin` does reset, "gets a way out" is false for the conflict case. The option leaves `refs/zn/pushed/<layer>` stale, so the layer is back where it was before the first walk. The same rebase conflicts again, and after `--continue` the check at `z-nile/engine/restackcmd.luau:262-265` refuses again. This is read from the code, not run.
- F3: Problem sentence 5 ("the only way on") and the need for a new option are disputed by `./zn finish`. At `z-nile/engine/main.luau:4417-4429` it force-pushes the layer with a lease on origin's tip and then writes `refs/zn/pushed/<layer>`. The red-check message in `restackplan.redMessage` already names `finish` then restack as the way on. The idea does not say why that is not the way out for a stuck layer. I read this and did not run it on a stuck worktree.
- F4: Solution sentence 3 states two conditions, but `restackplan.decide` (`z-nile/engine/restackplan.luau:70`) needs three: origin must also hold a commit the local layer lacks (`originExtra`). As worded, a local layer that is only ahead of a tip this clone did not push would be refused. Today it is not, and Non-goal 1 says `decide` keeps its rules.
- F5: Problem sentence 3 reads as the full list of routes to the refusal, and it is not. A run killed after the rebase and before its push (the `ZN_RESTACK_KILL=before-push` seam, or a kill during the check) leaves the same rebased, unpushed layer for the next plain restack. A hand amend or rebase after a `./zn commit` push is refused on the first walk, which Problem sentence 4 does not allow for. Solution sentence 2 promises only the three listed cases.

## Verdict

revise
