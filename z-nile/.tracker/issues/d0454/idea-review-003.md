# Idea review 003

## Findings

- F1: Problem sentence 5 is false as written. The refusal message at `z-nile/engine/restackcmd.luau:269` does name a zn command: it ends "then run ./zn restack <R-id> again; or ask whoever pushed it". The second half (the owner ran `git update-ref` by hand "more than once") cites no record, and I found none in the tracker, so a reader cannot check it.
- F2: No Solution sentence solves Problem sentence 5, and Non-goal 3 fences it out (wording kept, no new option, an already-refused worktree not fixed). Every refusal that survives still ends at the same message and the same hand `git update-ref`: a layer last pushed with plain `git push`, a clone that never pushed the layer, a worktree refused before this lands. Either the Solution leaves a stated problem unsolved, or sentence 5 is not part of this problem.
- F3: Solution sentence 2 claims "a restack goes through with no hand step" on all five routes, which is false on two of them. A conflict needs a hand resolution before `--continue`. After a red check, a plain restack runs the check again and stops red until the layer is fixed by hand. What the change delivers is that the layer is no longer refused as someone else's work; whether the restack "goes through" depends on the conflict and the check, so the sentence cannot be found true or false as it stands.
- F4: Solution sentence 3 says restack refuses a layer "only when all three of these hold", but restack refuses a layer for other reasons that stay: an emptied commit (`restackcmd.luau:274` and `:309`), a strayed layer on `--continue`, and a refused push. The sentence is true only of the "someone else's work" refusal, which it does not say.

## Verdict

revise
