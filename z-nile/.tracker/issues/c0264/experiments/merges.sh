#!/usr/bin/env bash
# c0264 landing orders, run as real merges against the current main (lesson c0308: redesign on the current main). For each
# open branch whose README change collides with the sections this issue rewrites, the README "as landed first" is made
# from README.base.md (main's README) plus that branch's own README change (git diff origin/main...<branch>); then the
# step-1 merge (git merge-file ours=landed base theirs=draft) is run and its conflicts counted, the resolution rule for
# those conflicts is applied to the draft, and ./zn check c0264 must give 10/10. Run from the prep worktree's root,
# through ./zn run. It writes z-nile/README.md and restores it from git on exit.
set -u
B=z-nile/.tracker/issues/c0264/experiments
T="$(mktemp -d)"
trap 'git checkout -q z-nile/README.md; rm -rf "$T"' EXIT
git fetch -q origin
resolved() { # <name> <conflicts> <perl rule applied to the draft>
	perl -0pe "$3" "$B/README.draft.md" >"$T/res.md"
	if cmp -s "$T/res.md" "$B/README.draft.md" && [[ ${3:-} != "" ]]; then echo "NOTE $1: the resolution rule changed nothing (the draft already holds the landed words)"; fi
	cp "$T/res.md" z-nile/README.md
	if ./zn check c0264 2>&1 | grep -q '^---- 10/10 criteria passed'; then echo "merge $1: $2 conflict(s) in git merge-file; after the resolution rule ./zn check c0264 10/10"; else echo "FAILED $1: $2 conflict(s); the resolved README does not pass ./zn check c0264"; fi
	git checkout -q z-nile/README.md
}
scenario() { # <name> <branch> <perl rule applied to the draft>
	local n
	git diff "origin/main...origin/$2" -- z-nile/README.md >"$T/p.patch"
	cp "$B/README.base.md" "$T/landed.md"
	patch -s "$T/landed.md" <"$T/p.patch" >/dev/null 2>&1 || { echo "BROKEN $1: its README change does not apply to the base"; return; }
	n="$(git merge-file -p "$T/landed.md" "$B/README.base.md" "$B/README.draft.md" | grep -c '^<<<<<<<')"
	resolved "$1" "$n" "$3"
}
# engine-z-work (PR #318, a person opens a CLI and runs z-work): it rewrites the worker-end line and the c0253 row. Rule: keep
# the draft's worker-end line, move #318's sentence to the start of The worker with its own `*exists*` (no ticket id) and drop
# its duplicate label; the row keeps the landed words. check.sh accepts the extra label place only when the merge base holds
# the z-work skill, which this checkout's does not, so here the scenario must fail AC7 with exactly that one label place and
# pass the rest; the 10/10 itself is `reasoned` until #318 lands (review 009 F4).
scenario_exists() { # <name> <branch> <perl rule>
	local n out
	git diff "origin/main...origin/$2" -- z-nile/README.md >"$T/p.patch"
	cp "$B/README.base.md" "$T/landed.md"
	patch -s "$T/landed.md" <"$T/p.patch" >/dev/null 2>&1 || { echo "BROKEN $1: its README change does not apply to the base"; return; }
	n="$(git merge-file -p "$T/landed.md" "$B/README.base.md" "$B/README.draft.md" | grep -c '^<<<<<<<')"
	perl -0pe "$3" "$B/README.draft.md" >"$T/res.md"; cp "$T/res.md" z-nile/README.md
	out="$(./zn check c0264 2>&1)"; git checkout -q z-nile/README.md
	if grep -q '^FAIL  AC7' <<<"$out" && grep -q 'The worker|-' <<<"$out" && [[ "$(grep -c '^FAIL' <<<"$out")" == 1 ]]; then echo "merge $1: $n conflict(s) in git merge-file; after the resolution rule only AC7 differs, by the label place The worker|- (accepted once the base holds the z-work skill)"; else echo "FAILED $1: $n conflict(s); unexpected check result"; fi
}
scenario_exists engine-z-work-first engine-z-work 's/(\n### The worker\n)/$1Today a person can run `z-work` in the CLI they opened: that session takes the next prepared raft and carries it layer by layer to `.\/zn done`, then stops. *exists*\n\n/; s/\| the worker: `z-work`, `\.\/zn work`, one raft to merge \| c0253 \| captured \|/| `.\/zn work` pull loop (the interactive session worker exists; the headless loop does not) | c0253 | captured |/'
# proto-c0248 (stacked delivery): rewrites the Stacked delivery section, the c0248 row and the "one raft" prose. Rule: keep the
# draft, which already says one raft, one bind and each ticket completed before the next; the landed row's state is the
# tracker's (captured until c0248 is done).
scenario c0248-first proto-c0248 's/x\A//'
# proto-c0265-raft (the heartbeat's first layer): a labelled Order bullet and a Roadmap row. Rule: fold its words into the
# draft's lost-first bullet under one label (the tracker's state), the row keeps its words; never two bullets or two rows.
scenario c0265-first proto-c0265-raft 's/- Lost work comes first: anything in progress whose heartbeat is stale \(`.\/zn lost` lists it\) comes before anything not yet started, whatever its rank, even when a person started it without changing its rank\. \*captured\* \(c0265\)/- Lost work comes before rank: a claim whose heartbeat went quiet (`.\/zn lost`) is taken before anything not yet started, whatever its rank, even when a person started it without changing its rank. *captured* (c0265)/; s/\| the heartbeat branch, `.\/zn beat`, lost work \| c0265 \| captured \|/| work heartbeat, `.\/zn beat`, `.\/zn lost` | c0265 | captured |/'
# proto-c0274: the same two lines plus a c0274 row. Rule as c0265's, and the c0274 row keeps its words.
scenario c0274-first proto-c0274 's/- Lost work comes first: anything in progress whose heartbeat is stale \(`.\/zn lost` lists it\) comes before anything not yet started, whatever its rank, even when a person started it without changing its rank\. \*captured\* \(c0265\)/- Lost work comes before rank: a claim whose heartbeat went quiet (`.\/zn lost`) is taken before anything not yet started, whatever its rank, even when a person started it without changing its rank. *captured* (c0265)/; s/\| the heartbeat branch, `.\/zn beat`, lost work \| c0265 \| captured \|/| work heartbeat, `.\/zn beat`, `.\/zn lost` | c0265 | captured |/; s/\| take over a lost claim, the old owner told \| c0274 \| captured \|/| take over a lost claim (`status <id> preparing`, `beat --adopt`) | c0274 | captured |/'
# proto-c0277 (the largest row set: c0265, c0274, c0275 and c0277 rows at once). Rule as c0265's, each landed row keeping its words.
scenario c0277-first proto-c0277 's/- Lost work comes first: anything in progress whose heartbeat is stale \(`.\/zn lost` lists it\) comes before anything not yet started, whatever its rank, even when a person started it without changing its rank\. \*captured\* \(c0265\)/- Lost work comes before rank: a claim whose heartbeat went quiet (`.\/zn lost`) is taken before anything not yet started, whatever its rank, even when a person started it without changing its rank. *captured* (c0265)/; s/\| the heartbeat branch, `.\/zn beat`, lost work \| c0265 \| captured \|/| work heartbeat, `.\/zn beat`, `.\/zn lost` | c0265 | captured |/; s/\| take over a lost claim, the old owner told \| c0274 \| captured \|/| take over a lost claim (`status <id> preparing`, `beat --adopt`) | c0274 | captured |/; s/\| automatic heartbeats \| c0275 \| captured \|/| automatic heartbeats (first beat, every command, long commands, the background beater, the dispatcher) | c0275 | captured |/; s/\| discard and recover a worktree: the numbered copy \| c0277 \| captured \|/| discard and recover a worktree (`worktree --takeover`, numbered copies, the discard marker, the sweep) | c0277 | captured |/'
