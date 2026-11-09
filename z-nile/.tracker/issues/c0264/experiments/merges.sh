#!/usr/bin/env bash
# c0264 landing orders, run as real merges. For each issue whose own PR edits z-nile/README.md in the sections this issue
# rewrites, the README "as landed first" is made from README.base.md with that issue's edit; then the step-1 merge
# (git merge-file ours=landed base theirs=draft) is run and its conflicts counted, and the resolution rule for that
# conflict is applied and the result checked with ./zn check c0264 (it must pass). Run from the prep worktree's root,
# through ./zn run. It writes z-nile/README.md and restores it from git on exit.
set -u
B=z-nile/.tracker/issues/c0264/experiments
trap 'git checkout -q z-nile/README.md' EXIT
scenario() { # <name> <perl edit a landed PR makes to the base README> <perl resolution applied to the draft>
	local landed conflicts
	landed="$(mktemp)"; perl -0pe "$2" "$B/README.base.md" >"$landed"
	cmp -s "$landed" "$B/README.base.md" && { echo "BROKEN $1: the landed edit did not apply"; return; }
	conflicts="$(git merge-file -p "$landed" "$B/README.base.md" "$B/README.draft.md" | grep -c '^<<<<<<<')"
	perl -0pe "$3" "$B/README.draft.md" >"$landed"
	perl -0e '
		open(D, "<", "'"$B"'/README.draft.md"); local $/; my $d = <D>; close D;
		open(R, "<", "'"$landed"'"); my $r = <R>; close R;
		my ($a) = $d =~ /(## Intent\n.*?)\n## The five parts\n/s; my ($b) = $r =~ /(## Intent\n.*?)\n## The five parts\n/s;
		open(M, "<", "z-nile/README.md"); my $m = <M>; close M;
		$m =~ s/## How it should work\n.*?(?=\n## The five parts\n)/$b/s; print $m;' >"$landed.out"
	cp "$landed.out" z-nile/README.md
	if ./zn check c0264 2>&1 | grep -q '^---- 10/10 criteria passed'; then echo "merge $1: $conflicts conflict(s) in git merge-file; after the resolution rule ./zn check c0264 10/10"; else echo "FAILED $1: $conflicts conflict(s); the resolved README does not pass ./zn check c0264"; fi
	git checkout -q z-nile/README.md; rm -f "$landed" "$landed.out"
}
# c0261 (models per activity): its PR rewrites the c0251 line that names models. Rule: keep c0261's wording of the
# parenthesis and the draft's labels on that line.
scenario c0261-first 's/\(author Sonnet, round one Opus through `claude` or `agent`, round two `grok-4\.7-xhigh` through `grok`\)/(the author and the reviewer on different model families)/' \
	's/\(author Sonnet, round one Opus through `claude` or `agent`, round two `grok-4\.7-xhigh` through `grok`\)/(the author and the reviewer on different model families)/'
# c0265 (heartbeat): the real prototype of its first layer (`proto-c0265-raft`, 8d326f59; its README diff is
# experiments/c0265-proto-readme.patch) adds a labelled Order bullet ("Lost work comes before rank: ... `./zn lost` ...
# *exists* (c0265)") and a Roadmap row. Rule: fold its words into the draft's lost-first bullet under one label (the
# tracker's state) and take its row words in the draft's row; never two bullets or two rows.
landed_c0265="$(mktemp)"; git apply --check "$B/c0265-proto-readme.patch" 2>/dev/null
cp "$B/README.base.md" "$landed_c0265"; patch -s "$landed_c0265" <"$B/c0265-proto-readme.patch" >/dev/null 2>&1 || echo "NOTE: the prototype patch does not apply cleanly to the base"
conflicts="$(git merge-file -p "$landed_c0265" "$B/README.base.md" "$B/README.draft.md" | grep -c '^<<<<<<<')"
perl -0pe 's/- Lost work comes first: anything in progress whose heartbeat is stale \(`.\/zn lost` lists it\) comes before anything not yet started, whatever its rank, even when a person started it without changing its rank\. \*captured\* \(c0265\)/- Lost work comes before rank: a claim whose heartbeat went quiet (`.\/zn lost`) is taken before anything not yet started, whatever its rank, even when a person started it without changing its rank. *captured* (c0265)/; s/\| the heartbeat branch, `.\/zn beat`, lost work \| c0265 \| captured \|/| work heartbeat, `.\/zn beat`, `.\/zn lost` | c0265 | captured |/' "$B/README.draft.md" >"$landed_c0265"
perl -0e 'open(D,"<","'"$landed_c0265"'"); local $/; my $r=<D>; close D; my ($b)=$r=~/(## Intent\n.*?)\n## The five parts\n/s; open(M,"<","z-nile/README.md"); my $m=<M>; close M; $m=~s/## How it should work\n.*?(?=\n## The five parts\n)/$b/s; print $m;' >"$landed_c0265.out"; cp "$landed_c0265.out" z-nile/README.md; rm -f "$landed_c0265.out"
if ./zn check c0264 2>&1 | grep -q '^---- 10/10 criteria passed'; then echo "merge c0265-first (real prototype 8d326f59): $conflicts conflict(s) in git merge-file; after the resolution rule ./zn check c0264 10/10"; else echo "FAILED c0265-first (real prototype): $conflicts conflict(s); the resolved README does not pass ./zn check c0264"; fi
git checkout -q z-nile/README.md; rm -f "$landed_c0265"
# c0260 (capture interview): its PR adds its own Roadmap row. Rule: one row per issue: keep the landed row's words in
# the draft's place, never a second row.
scenario c0260-first 's/(\| `.\/zn land` usage and a cheap retry \| c0258 \| captured \|\n)/$1| the capture interview, idea review and confirmation | c0260 | captured |\n/' \
	's/\| the capture interview and the idea review \| c0260 \| captured \|/| the capture interview, idea review and confirmation | c0260 | captured |/'
