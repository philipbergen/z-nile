# Idea review 001

## Findings

- F1: The Solution is broader than the scan, so it is not the smallest fix. The whole-tree specs read their roots minus skipped folders. c0193's lint covers `z-nile/`, `scripts/` and `pickman/scripts/`, but skips `.tracker/`, `tests/acceptance`, `tests/fixtures`, `vendor` and `.cache`, and reads only `.luau` files that are not `*.spec.luau`. The Solution says "any change to any file under a whole-tree spec's declared roots selects that spec". Read that way, an edit to a tracker document, a promoted spec or a fixture under `z-nile/` would pull in the meta, tree and scanners specs, including the 76,955-text hostile sweep, even though they never read that file. The smallest fix selects a spec when a changed file is one it would scan: under its declared roots, outside its declared skips, and of the kind it reads. It does not select on every file under the roots.

## Verdict

revise
