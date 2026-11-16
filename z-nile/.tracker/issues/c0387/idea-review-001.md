# Idea review 001

## Findings

- F1: The Solution is bigger than the problem needs. It requires all seven fence specs to be selected, but they all run the same scan over the same checkout: each home's `tests/meta/fence.spec.luau` is one line, `require(".../z-nile/tests/tooling/repo-fence.spec")`, and `checkout` is the git top level. The gate that let the spec through is `./zn done`'s `z-nile/check.sh --affected` on the done tree (`z-nile/engine/main.luau:5178`), and that gate runs every project. So selecting only z-nile's repository fence would have stopped R0112. Selecting all seven doesn't block anything more, and it costs a lot. The `pickman_fence` call scan reads every tracked `*.luau` and `*.sh` outside `.tracker/` and `tests/acceptance/`, so almost any change would run that scan, plus the fence's jail and hook probes, seven times instead of once.

## Verdict

revise
