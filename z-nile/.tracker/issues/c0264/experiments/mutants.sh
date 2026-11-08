#!/usr/bin/env bash
# c0264 mutation check: each mutant of the draft must fail at least the named criterion of ./zn check c0264.
# Run from the prep worktree's root: it writes z-nile/README.md and restores it from git when done.
set -u
D=z-nile/.tracker/issues/c0264/experiments/README.draft.md
trap 'git checkout -q z-nile/README.md' EXIT
run() { # <name> <criterion> <perl substitution>
	perl -0pe "$3" "$D" >z-nile/README.md
	if cmp -s "$D" z-nile/README.md; then echo "BROKEN $1: the edit did not apply"; return; fi
	if ./zn check c0264 2>&1 | grep -q "^FAIL  $2:"; then echo "killed $1 ($2)"; else echo "SURVIVED $1 ($2)"; fi
}
run no-intent AC1 's/\n## Intent\n/\n## Purpose\n/'
run intent-after-how AC1 's/(\n## Intent\n.*?)(\n## How it should work\n)/$2$1\n/s'
run intent-claims-built AC3 's/(## Intent\n[^\n]*)/$1 *exists*/'
run intent-no-economy AC2 's/(## Intent\n.*?)\*\*It stays cheap\.\*\*[^\n]*\n/$1/s'
run full-force-unlabelled AC4 's/\*captured\* \(c0262\)/(c0262)/'
run worker-rule-weakened AC5 's/clears its context and picks up the next raft whenever a raft ends/clears its context when a raft is merged/'
run no-deepseek AC6 's/`deepseek`/`ds`/g'
run cheap-tier-wrong AC6 's/4\.6 at high/4.7 at high/'
run row-overclaims AC7 's/\| c0261 \| captured \|/| c0261 | exists |/'
run label-moved AC7 's/ \*captured\* \(c0263\)//; s/(### Trust\n)/$1*captured* (c0263) /'
run c0117-lags AC7 's/\| c0117 \| exists \|/| c0117 | designed |/'
run skills-line-added AC8 's/(\n## Skills\n)/$1A false line.\n/'
