---
title: A regression guard that leans on "the gate runs everything" names the slow-tier specs and runs them by name
when: design
tags: [regression, slow-tier, gate, checks]
check: For each existing spec the Regression guard names as at risk, is it in `z-nile/tests/slow.tsv`? If so, which line of this issue's `check.sh` runs it by name, since no gate runs the slow tier without `--slow`?
---
"The raft's gate runs all of the project" is false for the slow tier: the gate, `./zn finish` and a tooling merge gate all leave it out.

**Why:** c0256, R0093 code review 001 F4: the design named `c0117/control-cli`, `c0117/dispatch-cli` and `c0117/trackerstate` as the specs most at risk and said the raft's gate would run them. All three are slow-tier, so nothing in the raft ran them after the prep's prototype run, on a `main` that had since changed the file under test.

**How to apply:** look each at-risk spec up in `slow.tsv` at prep; give the slow ones a `check` line of their own in `check.sh` (a one-time run, never promoted), with the time it takes in a comment.

**Note (c0306's prep, 2026-11-14, design review 001 F4):** when the at-risk slow specs are many and are Overrides the change edits, a check.sh line that runs them costs their whole time at every `finish`, `restack` and `done` (c0306's eleven take about 920 s; lesson zz-test/check-sh-never-runs-the-slow-tier). c0306 instead gives each a fast text criterion that fails on today's file (each hand-written review gains its record), runs `z-nile/check.sh --slow -- <the paths>` once on the prototype, and makes the Verification log quote that run at execution.
