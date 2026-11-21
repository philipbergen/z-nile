# Idea review 001

## Findings

- F1: The third Solution bullet can't be judged true or false, and it clashes with the third Non-goal. It doesn't say which copy of the branch counts as "already based on the layer below": the worker's local branch or `origin`'s. It also never says what a "recorded" conflict resolution is: a local commit, a pushed commit, or git's own record of how a conflict was resolved last time. This matters because of the code. `cmd.restack` takes each layer's tip from `origin` first (`layergit.layerTip`, `z-nile/engine/layergit.luau:249`), checks whether that remote tip is already stacked, then runs `git reset --hard` to it (`z-nile/engine/main.luau:4319` and `4355`). So a hand rebase the worker did only locally still fails the check and is wiped out, which is the loss Problem 2 describes. Fixing that means changing how restack picks a layer's tip on runs that meet no conflict, and the third Non-goal says the idea won't change those runs. The bullet should name the branch copy (local or remote) it trusts and what counts as a recorded resolution. Then either that Non-goal gets narrowed or the bullet does.

## Verdict

revise
