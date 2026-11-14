# Idea review 001

## Findings

- F1: Solution bullet 3 can't be judged true or false as written. Layers don't land one at a time. `./zn done` merges only the top layer's commit into main with `git merge --no-ff` (z-nile/engine/stack.luau:19-27), so "when the layer lands" has no clear meaning for layer 1. The bullet also says what happens on a real conflict but not what happens to a layer that is behind origin/main and has no conflict: does it land, or is it refused? If "checked whether current" means it is refused unless it contains origin/main's tip, then the race in Problem 2 moves from `./zn finish` to `./zn done` and isn't solved.

## Verdict

revise
