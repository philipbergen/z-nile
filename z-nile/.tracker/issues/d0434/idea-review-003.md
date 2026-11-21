# Idea review 003

## Findings

- F1: The third Solution bullet leaves out the most likely case after a hand rebase. That is when the local branch holds commits `origin` lacks but neither contains `origin`'s tip nor sits on the current tip of the layer below. For example, the worker hand-rebases layer 1 onto main, main moves again before they run `./zn restack`, and now layer 1's local branch is rebased onto an older main. The same happens to layer 2 once restack moves layer 1. Both conditions fail, so the bullet doesn't say to use the local tip. It also forbids `git reset --hard`, and no bullet says what restack does next. Today's code (`layergit.layerTip` prefers `origin/`, then `reset --hard tip` at `z-nile/engine/main.luau:4355`) would rebase `origin`'s stale tip. That hits the same conflict again or pushes a result without the hand resolution, which is the harm the second Problem bullet describes. The idea should say either that restack rebases from the local tip whenever the local branch holds commits `origin` lacks, or that it stops and names the layer in this case.

## Verdict

revise
