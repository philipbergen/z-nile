---
title: A round that changes a check.sh or a spec waits for the prototype's CI on both gates
when: design
tags: [specs, check-sh, regression]
check: Does every CI run the document cites have its result, green on every gate, for the commit this round reviews, and did the prototype carry this round's check.sh and specs (sequestered and at their promoted place) when it ran?
---
`./zn check <id>` runs an item's criteria; it never runs the repository-wide scans, which judge the text of every unfinished item's `check.sh` and every promoted spec: repo-fence (names that switch a guard off, `env -i` and `sandbox-exec` among them) and c0120's check-paths (every path a check.sh names must exist from its home). A criterion can pass 7 of 7 locally and still turn both gates red the moment the prep lands.

**Why:** c0132 round 2 rewrote its check.sh (a real jailed run in a fixture, which named the runner's marker and a copy list of paths missing from `z-nile/`) and its spec (which read the run's lock), and pushed the round citing CI as pending. The run failed both gates; design review 002 F1 found it.

**How to apply:** put the round's check.sh and spec in the prototype, the spec at its promoted place too, with any allow-list entry the design adds; run the two scans (`lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/acceptance/c0120/check-paths.spec.luau` from `z-nile/`) and `z-nile/ci-verify.sh` (both gates); push the round only once the run is green, and cite it by id and commit.
