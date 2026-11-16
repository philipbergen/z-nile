# Idea review 001

## Findings

- F1: The non-goal contradicts Solution 3, so it doesn't work as a fence. It says this chore changes nothing outside c0282's sequestered spec and frontmatter. But `z-nile/.tracker/issues/c0282/approval.md` pins the hash of `lifecycle.spec.luau` (`9cb134d6…`) and of the design. Editing the spec breaks that approval. The re-prep that Solution 3 requires then has to append a new approval row and write a new design review, and probably design text recording the layer-branch run too. All of those are c0282 files outside the spec and frontmatter, so as worded the non-goal is false the moment the solution is carried out. The other claims hold up. The lifecycle spec calls `clone.isolated(root, dir)`, removes origin, and runs `start` without ever naming `main`. c0302's scan in its prep matches that pattern. c0302's run on a layer branch (E1) lists both `c0074/done-gate` and `c0001/tracker-lifecycle` among the seven specs that fail there.

## Verdict

revise
