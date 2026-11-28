# Idea review 003

## Findings

- F1: The Non-goal on `./zn stop` cites `z-nile/engine/main.luau:2623` as part of `./zn stop`, but that line is in `cmd.release` (`./zn release <R-id>`, `main.luau:2558`). Release stamps every item that carries the raft's `preparing-…` claim back to `prepared` when its design on origin/main is ready, without going through `./zn status ... prepared`. So the fence names the wrong command for that line, `./zn release` is neither checked nor fenced, and the Solution's "is checked when it is next marked prepared" is false on that path.
- F2: Check (d) and `boundcmd.isTooling` exempt only targets in `TOOLING`, but the hook's own test is `TOOLING[t] == true or homeRunner(t)` (`z-nile/engine/boundcmd.luau:254`, `homeRunner` at `:213`). `lune run arcade/tests/run` (and the same for portal, snake, invaders, asteroids) therefore runs bare under the hook, yet (d) would refuse a `run` entry that records it. "The engine keeps one list of the gate's own tooling, not two" does not give the hook's answer for the spec runner the lesson exempts.
- F3: (d) does not say which state an entry has when its opening parenthesis holds more than one state word. `(not run)` itself holds `run`, and existing entries open `(executor, Phase 1)` and `(run in prep: PASS)`. A reader cannot tell whether `(not run)` or `(to run in Phase 1)` owes a command, so "whose state is `run`" cannot be found true or false for them.

## Verdict

revise
