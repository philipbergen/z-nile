# Idea review 001

## Findings

- F1: "design under review" is not a term z-nile defines, so the five Solution sentences can't be judged true or false, and the non-goal "which designs count as under review do not change" fences a rule that doesn't exist. Today `cmd.approve` (`z-nile/engine/main.luau:5711`) has no idea of "under review": it reads the item in the current checkout and requires `design: ready`, and a grep of the skills, README and engine finds the phrase only in an unrelated lesson. Every worktree checks out every issue's document. Once a prep has landed, every worktree branched from main afterwards also has that issue at `design: ready`. Without a stated test for when a worktree "holds" an item's design under review (for example: its branch differs from origin/main in the item's folder and the item is `design: ready` there), it can't be said whether `./zn approve <id>` finds exactly one worktree. That matters most for a re-approval after the contract changes (`approval.luau:133`), where the id form could be refused as "more than one" in the normal case.

## Verdict

revise
