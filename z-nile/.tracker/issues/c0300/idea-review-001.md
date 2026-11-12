# Idea review 001

## Findings

- F1: Solution 2 asks for more than the problem needs, and part of it can't be done. The problem is that a branch can be left on a truncated commit. The solution instead asks that "the layer branch and its remote" be back where they started after any failure or interruption. Restack works one layer at a time: it rebases a layer, pushes it, then moves on, and it stops at the first conflict (`z-nile/engine/main.luau:3870-3940`). So when it fails at layer 3, layers 1 and 2 have already moved and been pushed. If "the layer" means every layer, restack has to become all-or-nothing across the whole stack and undo pushes it already made, which overturns the "stop at the first conflict" contract in `z-nile/engine/stack.luau:13-14`. Separately, a hard kill that lands between the push and the local update leaves one ref moved and the other not, so no implementation can promise both are restored. The smaller claim, which a test can check, is: after a restack fails or is interrupted, neither the layer branch nor its remote points at a commit set missing one the layer held before.
- F2: Solution 1 says the layer "holds every commit it held before". Read literally, a successful rebase can never meet that, because rebasing gives every commit a new SHA. The only way left to satisfy the sentence is the "refuse" branch. It should say what is kept: one commit for each earlier commit, with the same subject and the same change, in the same order.

## Verdict

revise
