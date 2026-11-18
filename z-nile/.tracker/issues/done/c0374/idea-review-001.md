# Idea review 001

## Findings

- F1: The Problem gives three causes, but only one of them is true on main. I ran `tests/acceptance/c0120/finished.spec.luau` and got 10 hits, all `./zn (from z-nile)`. They come from quoted text that done c0264 passes to its `vocabulary` helper and that done d0333 passes to `cases` and `check`. That is the third misreading. No hit comes from a command after a cd to the repo root. The spec never reads Touched entries either: its rule is that a path resolves from the home or was already missing before the move. So the first cause cannot apply to it. Because of this, the Solution is bigger than the problem. Taking all of c0371's rules would bring in the Touched-entry rule, so a missing finished path that a Touched entry covers would start to pass. That loosens AC11's finished half, which the Non-goals don't fence off. It would also make c0374 wait on c0371's scanner, which isn't designed yet. The smallest fix is to stop reading quoted text passed to a check's own helper as a path.

## Verdict

revise
