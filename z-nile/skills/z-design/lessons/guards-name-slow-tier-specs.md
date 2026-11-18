---
title: A regression guard that leans on "the gate runs everything" names the slow-tier specs and runs them by name
when: design
tags: [regression, slow-tier, gate, checks]
check: For each existing spec the Regression guard names as at risk, is it in `z-nile/tests/slow.tsv`? If so, which line of this issue's `check.sh` runs it by name, since no gate runs the slow tier without `--slow`?
---
"The raft's gate runs all of the project" is false for the slow tier: the gate, `./zn finish` and a tooling merge gate all leave it out.

**Why:** c0256, R0093 code review 001 F4: the design named `c0117/control-cli`, `c0117/dispatch-cli` and `c0117/trackerstate` as the specs most at risk and said the raft's gate would run them. All three are slow-tier, so nothing in the raft ran them after the prep's prototype run, on a `main` that had since changed the file under test.

**How to apply:** look each at-risk spec up in `slow.tsv` at prep; give the slow ones a `check` line of their own in `check.sh` (a one-time run, never promoted), with the time it takes in a comment.

**Note** (R0100 design review 002 F2): a raft's composition proof names, for each command its members change (stop, ready, status, worktree, dispatch), the `slow.tsv` specs that drive it, and runs the slow tier once on the stack with `z-nile/check.sh --slow --project z-nile`, comparing its reds with the same specs on `origin/main`; a re-prep that changes such a command reruns it. Run it on a worktree that sits on a branch, because the fixtures clone the checkout: a detached HEAD no branch points to gave 29 false reds ("no main branch"). Ask: where is the slow-tier run on the current stack recorded, and are its reds the same as main's?

**Note (c0306's prep, 2026-11-14, design review 001 F4):** when the at-risk slow specs are many and are Overrides the change edits, a check.sh line that runs them costs their whole time at every `finish`, `restack` and `done` (c0306's eleven take about 920 s; lesson zz-test/check-sh-never-runs-the-slow-tier). c0306 instead gives each a fast text criterion that fails on today's file (each hand-written review gains its record), runs `z-nile/check.sh --slow -- <the paths>` once on the prototype, and makes the Verification log quote that run at execution.

**Note** (c0278 design review 001 F3): "the full gate at the merge runs it" is false for a slow-tier spec too: `--full` is every spec outside the slow tier. When the at-risk slow specs total far more than a check.sh can pay (c0278's seven, about 1,590 s), an Implementation step runs them once with `z-nile/check.sh --slow -- <paths>` on the finished layer and on `origin/main`, and the Verification log records the same reds; slow specs that stay in check.sh carry their seconds beside the line.

**Note** (R0129 code review 001 F2, f0399, 2026-11-17): the executor's Verification log said `approve.spec` and `approve-publish.spec` "needed no change (they pass)". Both are in the slow tier, so neither `--affected` nor `finish` had run them, and both were red, with `stack-land.spec`, which the Regression guard had predicted would pass. A log line that says a slow-tier spec passes needs that spec run by name. The executor runs `z-nile/check.sh --slow` once on the finished layer before the code review and compares every red with `origin/main` (here ten cases in eight files were red on both, none from the raft).

