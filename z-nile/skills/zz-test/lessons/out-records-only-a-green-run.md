---
title: The runner's --out record is written only when the whole run passes
when: both
tags: [check-sh, runner, specs]
check: Does a check.sh that runs a spec once and looks up each criterion's cases in the `--out` record say, when a case is missing, that one red case anywhere in that run empties the record, and point to the run's FAIL lines rather than naming the case it looked up as the one that failed?
---
`lune run z-nile/specs -- run --out FILE` writes the passing case names only when the run's exit code is 0 (`z-nile/specs.luau`, `if outFile ~= nil and code == 0`). A check.sh that runs a building spec once (the `fixtureSpec` pattern) and greps the record for each criterion's cases therefore reports every criterion of that spec as "did not pass: <its first case>" when any single case is red. The pass or fail result is still right, since nothing passes falsely. The message is wrong, and in a mutation run it hides which case killed the mutant.

**Why:** c0306 prep (2026-11-14). The prototype's author reported it, and the runner's code confirms it. c0306's check.sh carried the comment "the runner writes each passing case's name to the --out file", copied from earlier checks. That comment is true only for a green run.

**How to apply:** in a check.sh that reads the record, make the miss message say that the run had a red case, and to read its FAIL lines above. In a mutation check, read the runner's FAIL lines for the killing case, not the check.sh summary. d0329 is the fix.

**Note (c0251's prep, 2026-11-15):** a check.sh that chains its `fixtureSpec … --run` calls with `&&` stops at the first red spec. Every criterion of each later spec then reads "did not run", hiding which specs pass. Run every spec, combine the results afterwards, and let each criterion read its own record.
