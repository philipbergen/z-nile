# Idea review 001

## Findings

- F1: The fourth Solution sentence ("a path that exists nowhere and is in no Touched entry is still reported") and the second non-goal ("a really missing path") set a lower bar than the spec has now. Today the spec reports any path that is missing from its item's home. That includes a path that exists elsewhere: the spec's own fixture reports z-nile's `test -f src/server`, although `pickman/src/server` exists. Under "exists nowhere", a shortcut fix would pass the idea: look up every path from the home or, failing that, from the repo root. That one change clears c0292's `z-nile/roots` without the cd rule in the second Solution sentence. It also lets a z-nile check run `git diff --quiet -- scripts/…` with no cd and pass on a path missing from where the command runs, which is the very case c0120 AC11 exists to catch. So the non-goal fences nothing a reader can test. The sentence should say that a path missing from where its command runs (the item's home, or the repo root after a cd there) is still reported.

## Verdict

revise
