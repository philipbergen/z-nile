# Idea review 001

## Findings

- F1: The Solution only fixes the trailing `-` ("no trailing `-`"), and that doesn't give "that directory's real project folder name" for a worktree. Claude Code turns `.` into `-` as well as `/`. In `~/.claude/projects` there are 45 `…-pickman--worktree-…` folders, including this worktree's `-Users-philipbergen-code-pickman--worktree-capture-idea-batch-2`, and none spelled `-.worktree`. But `sessionread.span` (`z-nile/engine/sessionread.luau:141`) only replaces `/`. So after the slash is stripped, `./zn spend` run from any `.worktree/<name>/` still looks under `…-pickman-.worktree-<name>`, finds nothing, and writes `unmeasured tokens,ai`. Every change is made in a worktree, so the fix as written misses most real runs. The Solution should say that the folder name maps `.` as well as `/`, or the Problem should be limited to directories with no `.` in their path.

## Verdict

revise
