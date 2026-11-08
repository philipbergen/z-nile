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
# c0265 (heartbeat): its PR adds a `./zn lost` line to Order. Rule: keep that line before the append-by-default bullet, with the draft's bullets around it.
scenario c0265-first 's/(- z-ticket and z-design append by default\.)/- `.\/zn lost` lists the lost claims, first.\n$1/' \
	's/(- z-ticket and z-design append by default\.)/- `.\/zn lost` lists the lost claims, first.\n$1/'
# c0260 (capture interview): its PR adds its own Roadmap row. Rule: one row per issue: keep the landed row's words in
# the draft's place, never a second row.
scenario c0260-first 's/(\| `.\/zn land` usage and a cheap retry \| c0258 \| captured \|\n)/$1| the capture interview, idea review and confirmation | c0260 | captured |\n/' \
	's/\| the capture interview and the idea review \| c0260 \| captured \|/| the capture interview, idea review and confirmation | c0260 | captured |/'
