# Idea review 001

## Findings

- F1: Solution 3 is the only sentence a reader can't mark true or false. "Shown as stale in a place a worker or the user already looks" names no place, and "a stated limit" doesn't say where the limit is stated. Any display anywhere would pass. Name the surface (for example, the board, or what `./zn work` prints) and where the limit lives. The other sentences can be checked, and Problem 3 holds: `z-nile/watch-passed` records only the commit of the last pass, with no time, and nothing in `z-nile/engine/watchcmd.luau` reports how long ago that was.

## Verdict

revise
