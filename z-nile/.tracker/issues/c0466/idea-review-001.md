# Idea review 001

## Findings

- F1: Problem 1 names finish and done as stages where the agent runs the spend command by hand, but both already record the running session's spend themselves (`z-nile/engine/main.luau:4383` for finish, `:5671` for done). That part of the sentence is false, and the "finishing, marking done" part of Solution 1 would be found true on main before any work. The one manual call left near done is the after-merge `./zn spend <R-id> --phase deliver` in zz-execute Phase 6, which the idea does not name.
- F2: "for claude, grok, kimi and agy" in Solution 1 cannot hold under the second non-goal. No reader measures an agy session (`z-nile/engine/sessionread.luau` reads claude, grok, Cursor's agent and kimi), and the running-session reader that finish and done use returns nothing for grok. The sentence does not say whether an `unmeasured` row counts as recording the spend, so a reader cannot find it true or false for those two CLIs.
- F3: Solution 2's "same session and stage" cannot be decided from a spend row, which has no session column (when, commit, lines, minutes, attribution, phase, tokens, model). "Stage" is also not tied to the row's phase: one session legitimately writes several `design-review` rows (the reviewer's run and the answer, each round), so read as "same phase" the rule drops real spend.
- F4: "the guard" in Problem 2 and Solution 3 names no single thing. The lesson to be graduated lists the type check, watch-check, `zn --help` and five guard specs (scanning-loops, c0193 tree, c0077 cache-paths, repo-fence, gatequeue), and `check.sh --static` runs no specs. A reader cannot tell which guard specs finish must run, or whether Solution 4 may graduate the whole lesson.
- F5: Problem 1 counts the review stage, where z-design asks for a second manual call when a round is answered (`./zn spend <id> --phase design-review --note design-refute-NNN`). Solution 1 has an event only for dispatching the review, so the forgotten-call problem remains for the answer.

## Verdict

revise
