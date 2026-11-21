# Idea review 002

## Findings

- F1: The Solution never says that restack must run check.sh on a layer and push it when the layer's stacked tip exists only on the local branch. Two cases produce such a tip: a hand rebase, and a resolution finished with the continue command. Today restack takes the tip from `origin` first (`layergit.layerTip`, `z-nile/engine/layergit.luau:249`). It skips a layer that is already stacked without running check.sh and without pushing (`z-nile/engine/main.luau:4319`). It runs check.sh and pushes only after its own rebase (`main.luau:4366` and `4373`). `./zn done` also reads `origin` first (`main.luau:5489`). Under the third Solution bullet, a hand-rebased layer would count as "already stacked", so it gets no check.sh and no push. `./zn done` would then still find `origin` unstacked and reply "run ./zn restack", and restack would again print "already stacked", so the worker goes round in a loop. The second bullet also doesn't say whether the conflicted layer itself gets its check.sh and push before the remaining layers. A build could skip both and still meet every Solution sentence as written.

## Verdict

revise
