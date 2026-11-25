# Idea review 001

## Findings

- F1: The Problem's "the next restack that rebases that layer refuses" is false for a restack that runs straight through, so the "no conflict" half of Solution sentence 2 is already true today. Restack tests for someone else's work only when the local layer and origin's have already diverged as it reaches the layer (`z-nile/engine/restackcmd.luau:262`). Right after a `./zn commit` or `./zn approve` push the two are equal, so a clean restack rebases and pushes with no refusal. The refusal comes on a second walk over a layer that a stopped run left rebased and unpushed. That happens after a conflict and `--continue`, after a red check and a plain restack, and after a check that did not start (exit 75) and the rerun (d0434 design review 001 F1, probed there). The last two have no conflict, and the idea names neither.
- F2: Solution sentence 4 cannot be found true or false, and it conflicts with the fences. It names no command and does not say what that command goes by. In a stuck worktree nothing records that origin's tip is this clone's, and d0434's rule is that a fetch, a reset or a reflog proves nothing about who pushed. So the command either takes the person's word, which gets another clone's tip past the refusal just as well (against Solution sentence 3 and non-goal 2), or it infers from other evidence such as the stopped run's `judged` line, which changes how restack decides (against non-goal 1, and d0434 left that question open to the owner).
- F3: Solution sentence 3 is false as written. Restack refuses another clone's tip only when the local layer also holds a commit origin lacks. When the local layer has nothing of its own, restack takes origin's tip whoever pushed it (`restackplan.source`), and that has to stay.

## Verdict

revise
