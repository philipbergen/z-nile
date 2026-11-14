#!/usr/bin/env bash
# c0264 mutation check: each mutant of the draft must fail at least the named criterion of ./zn check c0264, and each
# correct variant must pass it. Run from the prep worktree's root, through ./zn run (it writes z-nile/README.md and
# restores it from git on exit and on INT/TERM, so a stopped run leaves no mutant behind).
set -u
ONLY=("$@") # mutant ids to run; none means all
D=z-nile/.tracker/issues/c0264/experiments/README.draft.md
restore() { git checkout -q z-nile/README.md; }
trap restore EXIT
trap 'restore; exit 130' INT TERM
apply() { perl -0pe "$1" "$D" >z-nile/README.md; ! cmp -s "$D" z-nile/README.md; }
want() { [[ ${#ONLY[@]} -eq 0 ]] && return 0; local w; for w in "${ONLY[@]}"; do [[ $w == "$1" ]] && return 0; done; return 1; }
run() { # <name> <criterion> <perl substitution>: a mutant
	want "$1" || return 0
	apply "$3" || { echo "BROKEN $1: the edit did not apply"; return; }
	if ./zn check c0264 2>&1 | grep -q "^FAIL  $2:"; then echo "killed $1 ($2)"; else echo "SURVIVED $1 ($2)"; fi
}
ok() { # <name> <criterion> <perl substitution>: a correct variant
	want "$1" || return 0
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
run tiers-back AC6 's/### Models per command and activity/### Model tiers/'
run wait-tier-back AC6 's/runs on the cheapest model\./runs on the wait tier./'
run heartbeat-on-main AC6 's/as a commit on a heartbeat branch, not on `main`;/pushed to `main`;/'
run no-cheapest-waiting AC6 's/; the cheapest do the waiting\./\./'
run model-names-back AC6 's/(### Models per command and activity\n.*?Nothing expensive orchestrates or waits\.)/$1 Haiku or composer wait./s'
run intent-model-names AC6 's/(\*\*It stays cheap\.\*\* )/$1Opus and grok 4.7 xhigh do the reviews. /'
run cheap-orchestrates AC6 's/it never orchestrates on an expensive one/it orchestrates on an expensive one/'
run no-approval-intent AC6 's/, and a person approves it\././'
run final-reviews-cheap AC6 's/(\*\*It stays cheap\.\*\* )Expensive models do every final review;/$1Cheaper models do every final review;/'
run final-reviews-cheap-section AC6 's/- Expensive models do every final review:/- Cheaper models do every final review:/'
run no-idea-review AC6 's/a clean adversarial reviewer on an expensive model checks that it says what the person said/a reviewer reads it/'
run rank-over-depends AC6 's/, so the order works around a blocked item without changing any rank//'
run human-start-ranked AC6 's/, even when a person started it without changing its rank//'
run full-force-not-fresh AC6 's/It runs on an expensive model in a fresh context/It runs in a fresh context/'
ok c0261-reworded AC6 's/\(author Sonnet, round one Opus through `claude` or `agent`, round two `grok-4\.7-xhigh` through `grok`\)/(the author and the reviewer on different model families)/'
ok c0261-reworded-diagram AC9 's/\(author Sonnet, round one Opus through `claude` or `agent`, round two `grok-4\.7-xhigh` through `grok`\)/(the author and the reviewer on different model families)/'
ok c0265-lost-line AC6 's/(- A worker that holds an item beats a heartbeat)/- `.\/zn lost` lists the lost claims, first.\n$1/'
run full-force-sees-compromises AC6 's/It sees no design reviews, refutes, harvests, PR comments or worker notes/It sees the design reviews, refutes, harvests, PR comments and worker notes/'
run no-one-context AC6 's/It keeps one context for the whole raft/It starts a fresh context on each ticket/'
run model-id-back AC6 's/(### Models per command and activity\n.*?Nothing expensive orchestrates or waits\.)/$1 Use grok-code-fast-1 or kimi-k2./s'
run takeover-labelled-c0265 AC7 's/\*captured\* \(c0274\)/*captured* (c0265)/'
run copy-labelled-exists AC7 's/\*captured\* \(c0277\)/*exists* (c0277)/'
run approval-label-dropped AC7 's/ \*captured\* \(c0283\)//'
run row-per-part-missing AC7 's/\| discard and recover a worktree: the numbered copy \| c0277 \| captured \|\n//'
run approval-not-refused AC6 's/ and `prepared` is refused until it has run//'
run duplicate-row AC10 's/(\| a real model for each command and activity \| c0261 \| captured \|\n)/$1| again | c0261 | captured |\n/'
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
