#!/usr/bin/env bash
# c0264 mutation check: each mutant of the draft must fail at least the named criterion of ./zn check c0264, and each
# correct variant must pass it. Run from the prep worktree's root, through ./zn run (it writes z-nile/README.md and
# restores it from git on exit and on INT/TERM, so a stopped run leaves no mutant behind).
set -u
D=z-nile/.tracker/issues/c0264/experiments/README.draft.md
restore() { git checkout -q z-nile/README.md; }
trap restore EXIT
trap 'restore; exit 130' INT TERM
apply() { perl -0pe "$1" "$D" >z-nile/README.md; ! cmp -s "$D" z-nile/README.md; }
run() { # <name> <criterion> <perl substitution>: a mutant
	apply "$3" || { echo "BROKEN $1: the edit did not apply"; return; }
	if ./zn check c0264 2>&1 | grep -q "^FAIL  $2:"; then echo "killed $1 ($2)"; else echo "SURVIVED $1 ($2)"; fi
}
ok() { # <name> <criterion> <perl substitution>: a correct variant
	apply "$3" || { echo "BROKEN $1: the edit did not apply"; return; }
	if ./zn check c0264 2>&1 | grep -q "^PASS  $2:"; then echo "passes $1 ($2)"; else echo "REFUSED $1 ($2)"; fi
}
run no-intent AC1 's/\n## Intent\n/\n## Purpose\n/'
run intent-after-how AC1 's/(\n## Intent\n.*?)(\n## How it should work\n)/$2$1\n/s'
run intent-claims-built AC3 's/(## Intent\n[^\n]*)/$1 *exists*/'
run intent-no-economy AC2 's/(## Intent\n.*?)\*\*It stays cheap\.\*\*[^\n]*\n/$1/s'
run full-force-unlabelled AC4 's/\*captured\* \(c0262\)/(c0262)/'
run worker-rule-weakened AC5 's/clears its context and picks up the next raft whenever a raft ends: when the raft is merged, or when it is blocked and the worker lets it go\./clears its context when a raft is merged./'
run worker-rule-split AC5 's/whenever a raft ends: when the raft is merged, or when it is blocked and the worker lets it go\./whenever a raft ends.\n- A raft ends when it is merged, or when it is blocked./'
run no-deepseek AC6 's/`deepseek`/`ds`/g'
run cheap-tier-wrong AC6 's/4\.6 at high/4.7 at high/'
run autonomy-skips-approval AC6 's/once a person has approved its design, an item is rafted/an item is designed, design-reviewed, rafted/'
run row-overclaims AC7 's/\| c0261 \| captured \|/| c0261 | exists |/'
run label-moved AC7 's/ \*captured\* \(c0263\)//; s/(### Trust\n)/$1*captured* (c0263) /'
run c0117-lags AC7 's/\| c0117 \| exists \|/| c0117 | designed |/'
run skills-line-added AC8 's/(\n## Skills\n)/$1A false line.\n/'
run skeleton-diagram AC9 's/(## How it should work\n.*?```mermaid\n).*?(\n```)/$1flowchart LR\n  subgraph eng["engineer end"]\n  end\n  subgraph wrk["worker end"]\n  end$2/s'
run diagram-one-way-out AC9 's/  esc -->\|"raft released: clear context"\| loop\n//'
run ends-float AC9 's/  layer -->\|"raft merged: clear context"\| loop\n//; s/  esc -->\|"raft released: clear context"\| loop\n/  note["raft merged: clear context; raft released: clear context"]\n/'
run todays-diagram AC9 'BEGIN { $old = `git show origin/main:z-nile/README.md`; ($old) = $old =~ /## How it should work\n.*?(```mermaid\n.*?\n```)/s } s/(## How it should work\n.*?)```mermaid\n.*?\n```/$1$old/s'
run edges-commented AC9 's/  layer -->/  %% layer -->/; s/  esc -->\|"raft released/  %% esc -->|"raft released/'
run node-renamed AC9 's/z-ticket: interview, idea, idea review, confirm/z-ticket: capture/'
run intent-rank-unexcepted AC6 's/, and giving a rank when a person wants one,//'
run rank-asked-of-no-one AC6 's/: with no one to answer, the rank stays unset//'
ok worker-rule-users-words AC5 's/A worker clears its context and picks up the next raft whenever a raft ends: when the raft is merged, or when it is blocked and the worker lets it go\./A worker clears itself and picks up the next raft whenever a raft is merged, or blocked and let go; its context does not carry over./'
