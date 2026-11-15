#!/usr/bin/env bash
# Acceptance checks for c0325. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0325 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0325"

# match, authorship and authorread are plain specs (pure, or folders under .cache). dispatch-env runs the real
# dispatcher against fake CLIs and authorcmd drives the real ./zn spend and commit in two fixtures. Each spec runs once, and
# every criterion then checks that each of its own cases passed: the runner writes each passing case's name to the --out
# file, but only when the whole run passes (z-nile/specs.luau), so one red case leaves the record empty and every
# criterion of that spec reports it (lesson zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0325-check"
fixtureSpec() {
	local file="$1" home rel out
	shift
	home="$(pwd -P)"
	rel="${A#"$home"/}/$file.spec.luau" # the runner takes the spec's path from the project home
	out="$OUT/$file.txt"
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "$OUT" && : >"$out" # an empty record when no case passes: each criterion then names the case that did not
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$out" -- "$rel") || true
	fi
	[[ -f $out ]] || { echo "$file.spec did not run"; return 1; }
	local c
	for c in "$@"; do
		grep -qxF "	$c" "$out" || { echo "did not pass: $c (or another case of $file.spec failed: the record is written only for a green run, so read its FAIL lines)"; return 1; }
	done
}

fastSpecs() {
	local s
	for s in \
		tests/acceptance/c0001/ci-workflow.spec.luau tests/acceptance/c0001/tracker-lifecycle.spec.luau tests/acceptance/c0005/worktree.spec.luau tests/acceptance/c0006/clone.spec.luau \
		tests/acceptance/c0007/changed.spec.luau tests/acceptance/c0008/done-order.spec.luau tests/acceptance/c0034/locator.spec.luau tests/acceptance/c0038/deferred.spec.luau \
		tests/acceptance/c0042/cli.spec.luau tests/acceptance/c0042/model.spec.luau tests/acceptance/c0042/page.spec.luau tests/acceptance/c0042/smoke.spec.luau \
		tests/acceptance/c0042/vendor.spec.luau tests/acceptance/c0043/format.spec.luau tests/acceptance/c0043/review-skill.spec.luau tests/acceptance/c0043/rounds.spec.luau \
		tests/acceptance/c0043/table.spec.luau tests/acceptance/c0043/ticket-prep.spec.luau tests/acceptance/c0044/guard.spec.luau tests/acceptance/c0044/naming.spec.luau \
		tests/acceptance/c0045/workstreams.spec.luau tests/acceptance/c0046/launch.spec.luau tests/acceptance/c0047/override-check.spec.luau tests/acceptance/c0048/board-docs.spec.luau \
		tests/acceptance/c0048/board-workflow.spec.luau tests/acceptance/c0049/par-stages.spec.luau tests/acceptance/c0049/parallel-runner.spec.luau tests/acceptance/c0049/spec-isolation.spec.luau \
		tests/acceptance/c0050/start-depends.spec.luau tests/acceptance/c0052/new-spacing.spec.luau tests/acceptance/c0052/renumber.spec.luau tests/acceptance/c0052/skill-doc.spec.luau \
		tests/acceptance/c0053/commands-claim.spec.luau tests/acceptance/c0053/commands-new.spec.luau tests/acceptance/c0053/commands-prep.spec.luau tests/acceptance/c0053/commands-start.spec.luau \
		tests/acceptance/c0053/commands-sync.spec.luau tests/acceptance/c0053/publish.spec.luau tests/acceptance/c0053/status.spec.luau tests/acceptance/c0055/setup-run.spec.luau \
		tests/acceptance/c0057/guard.spec.luau tests/acceptance/c0057/open.spec.luau tests/acceptance/c0058/fence.spec.luau tests/acceptance/c0058/lock.spec.luau \
		tests/acceptance/c0059/adapt.spec.luau tests/acceptance/c0060/fixture.spec.luau tests/acceptance/c0060/retrofit.spec.luau tests/acceptance/c0066/cleanup.spec.luau \
		tests/acceptance/c0067/paths.spec.luau tests/acceptance/c0067/publish-move.spec.luau tests/acceptance/c0067/ready.spec.luau tests/acceptance/c0068/stop.spec.luau \
		tests/acceptance/c0069/prompt.spec.luau tests/acceptance/c0070/board-refresh.spec.luau tests/acceptance/c0072/land.spec.luau tests/acceptance/c0073/board-stats.spec.luau \
		tests/acceptance/c0073/chart.spec.luau tests/acceptance/c0073/history.spec.luau tests/acceptance/c0073/stats.spec.luau tests/acceptance/c0074/done-gate.spec.luau \
		tests/acceptance/c0076/sweeper.spec.luau tests/acceptance/c0077/cache-paths.spec.luau tests/acceptance/c0077/replace-file.spec.luau tests/acceptance/c0078/jail-signals.spec.luau \
		tests/acceptance/c0079/watchdog.spec.luau tests/acceptance/c0080/consequences.spec.luau tests/acceptance/c0081/allocate.spec.luau tests/acceptance/c0081/compact.spec.luau \
		tests/acceptance/c0081/ids.spec.luau tests/acceptance/c0081/next-file.spec.luau tests/acceptance/c0081/publish-guard.spec.luau tests/acceptance/c0081/remap.spec.luau \
		tests/acceptance/c0081/renamed.spec.luau tests/acceptance/c0081/skill-doc.spec.luau tests/acceptance/c0082/audit.spec.luau tests/acceptance/c0082/cli.spec.luau \
		tests/acceptance/c0082/real-tree.spec.luau tests/acceptance/c0084/commit-phase.spec.luau tests/acceptance/c0084/ledger.spec.luau tests/acceptance/c0084/metrics-phases.spec.luau \
		tests/acceptance/c0084/spend-command.spec.luau tests/acceptance/c0107/keep.spec.luau tests/acceptance/c0107/label.spec.luau tests/acceptance/c0107/page.spec.luau \
		tests/acceptance/c0107/views.spec.luau tests/acceptance/c0111/harvest.spec.luau tests/acceptance/c0111/lesson-format.spec.luau tests/acceptance/c0111/lessons-cli.spec.luau \
		tests/acceptance/c0111/metrics-lessons.spec.luau tests/acceptance/c0111/prompt-lessons.spec.luau tests/acceptance/c0111/select.spec.luau tests/acceptance/c0111/skill-docs.spec.luau \
		tests/acceptance/c0111/trail.spec.luau tests/acceptance/c0114/classified.spec.luau tests/acceptance/c0114/compact-roots.spec.luau tests/acceptance/c0114/docs.spec.luau \
		tests/acceptance/c0114/finished.spec.luau tests/acceptance/c0114/gate-cover.spec.luau tests/acceptance/c0114/guards.spec.luau tests/acceptance/c0114/layout.spec.luau \
		tests/acceptance/c0114/publish-roots.spec.luau tests/acceptance/c0114/registry.spec.luau tests/acceptance/c0114/roots-cli.spec.luau tests/acceptance/c0114/trail-move.spec.luau \
		tests/acceptance/c0114/window.spec.luau tests/acceptance/c0115/absence.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0115/freeze.spec.luau \
		tests/acceptance/c0115/layout.spec.luau tests/acceptance/c0115/lessons.spec.luau tests/acceptance/c0115/prompt.spec.luau tests/acceptance/c0115/readme.spec.luau \
		tests/acceptance/c0115/skills.spec.luau tests/acceptance/c0115/trusted-base.spec.luau tests/acceptance/c0116/claims.spec.luau tests/acceptance/c0116/compact-record.spec.luau \
		tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0116/issue-design.spec.luau tests/acceptance/c0116/plan-cli.spec.luau tests/acceptance/c0116/plan.spec.luau \
		tests/acceptance/c0116/promote.spec.luau tests/acceptance/c0116/recombine.spec.luau tests/acceptance/c0116/retired.spec.luau tests/acceptance/c0117/adapters.spec.luau \
		tests/acceptance/c0117/control-cli.spec.luau tests/acceptance/c0117/dispatch-cli.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/docs.spec.luau \
		tests/acceptance/c0117/ledger.spec.luau tests/acceptance/c0117/models.spec.luau tests/acceptance/c0117/trackerstate.spec.luau tests/acceptance/c0117/wrapper.spec.luau \
		tests/acceptance/c0118/docs.spec.luau tests/acceptance/c0118/history.spec.luau tests/acceptance/c0118/metrics.spec.luau tests/acceptance/c0118/model.spec.luau \
		tests/acceptance/c0118/page.spec.luau tests/acceptance/c0118/real.spec.luau tests/acceptance/c0118/view.spec.luau tests/acceptance/c0119/capture-cli.spec.luau \
		tests/acceptance/c0119/scope-docs.spec.luau tests/acceptance/c0119/scope-lessons.spec.luau tests/acceptance/c0120/check-paths.spec.luau tests/acceptance/c0120/ci.spec.luau \
		tests/acceptance/c0120/docs.spec.luau tests/acceptance/c0120/finished.spec.luau tests/acceptance/c0120/freeze.spec.luau tests/acceptance/c0120/gate-homes.spec.luau \
		tests/acceptance/c0120/graph-homes.spec.luau tests/acceptance/c0120/homes.spec.luau tests/acceptance/c0120/layout.spec.luau tests/acceptance/c0120/old-roots.spec.luau \
		tests/acceptance/c0120/promote-home.spec.luau tests/acceptance/c0120/registry-home.spec.luau tests/acceptance/c0120/runner-home.spec.luau tests/acceptance/c0120/trail-home.spec.luau \
		tests/acceptance/c0127/reuse.spec.luau tests/acceptance/c0127/rules.spec.luau tests/acceptance/c0127/skill.spec.luau tests/acceptance/c0131/accept.spec.luau \
		tests/acceptance/c0131/refuse.spec.luau tests/acceptance/c0184/docs.spec.luau tests/acceptance/c0184/generic.spec.luau tests/acceptance/c0184/homes.spec.luau \
		tests/acceptance/c0184/skills.spec.luau tests/acceptance/c0191/boundcmd.spec.luau tests/acceptance/c0191/bounded.spec.luau tests/acceptance/c0191/docs.spec.luau \
		tests/acceptance/c0191/engine-cpu.spec.luau tests/acceptance/c0191/hooks.spec.luau tests/acceptance/c0191/reap.spec.luau tests/acceptance/c0191/runner-cpu.spec.luau \
		tests/acceptance/c0239/docs.spec.luau tests/acceptance/c0239/done.spec.luau tests/acceptance/c0239/land.spec.luau tests/acceptance/c0239/stop.spec.luau \
		tests/acceptance/c0244/homes.spec.luau tests/meta/architecture.spec.luau tests/tooling/affected.spec.luau tests/tooling/approve-publish.spec.luau \
		tests/tooling/approve.spec.luau tests/tooling/audit-raft-roots.spec.luau tests/tooling/audit-spec-left.spec.luau tests/tooling/board-review.spec.luau \
		tests/tooling/board.spec.luau tests/tooling/bounded-review.spec.luau tests/tooling/busy-holds-move.spec.luau tests/tooling/claim-taken.spec.luau \
		tests/tooling/dispatch-guards.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/fence-cache-entry.spec.luau tests/tooling/fence-every-home.spec.luau \
		tests/tooling/fence-inherited-env.spec.luau tests/tooling/fence-leftovers.spec.luau tests/tooling/fixture-elsewhere.spec.luau tests/tooling/game-roots.spec.luau \
		tests/tooling/gate-home-cache.spec.luau tests/tooling/idea.spec.luau tests/tooling/lessons-hidden.spec.luau tests/tooling/lock-start-ids.spec.luau \
		tests/tooling/metrics-rounds.spec.luau tests/tooling/migrate-odd.spec.luau tests/tooling/openlist.spec.luau tests/tooling/raftcheck.spec.luau \
		tests/tooling/ready-members.spec.luau tests/tooling/recombine-members.spec.luau tests/tooling/remap-once.spec.luau tests/tooling/repo-fence.spec.luau \
		tests/tooling/roles.spec.luau tests/tooling/run-guard-relaunch.spec.luau tests/tooling/run-lane-error.spec.luau tests/tooling/select-scope.spec.luau \
		tests/tooling/spend.spec.luau tests/tooling/stack-fix.spec.luau tests/tooling/stack-land.spec.luau tests/tooling/start-pr-reuse.spec.luau \
		tests/tooling/status-fresh.spec.luau tests/tooling/sweeper-interlock.spec.luau tests/tooling/trace-land.spec.luau tests/tooling/trace.spec.luau \
		tests/tooling/tracker-guarded.spec.luau tests/tooling/tracker-review-guards.spec.luau tests/tooling/watch-map.spec.luau tests/tooling/watch.spec.luau \
		tests/tooling/window-new-raft.spec.luau tests/tooling/worktree-fetch.spec.luau tests/tooling/wrapper-guards.spec.luau; do
		grep -qF "	$s" tests/slow.tsv || printf '%s\n' "$s"
	done
}
runFast() {
	local list
	list=$(fastSpecs)
	[[ -n $list ]] || { echo "no fast spec is listed"; return 1; }
	# shellcheck disable=SC2086 # one spec path per word
	lune run tests/run -- $list
}

ac1() {
	fixtureSpec match --run "AC1: a record is cut by the longest known model of any role or fallback, at any effort word" "AC1: a hyphenated effort word, an effort no role uses, a typed \`<model>-<effort>\` id and a record of a model at the author's effort that is no author try"
}
check "AC1: \`models.modelOf\` returns the bare model of a record that is any known model followed by an optional one marker and any effort word (hyphens included), and \`bareModel(record)\` for an unknown record." ac1
ac2() {
	fixtureSpec match "AC2: identical bracketed strings match; \`[1m]\` against plain matches both ways; \`[1m][2m]\` keeps \`[1m]\`" "AC2: a model that only starts with another model's name does not match"
}
check "AC2: \`authorship.isAuthor\` normalises both sides with \`bareModel\`: identical and mixed \`[1m]\`/plain strings match, \`[1m][2m]\` keeps one marker, and a model that only starts with another's name does not match." ac2
ac3() {
	fixtureSpec authorship --run "AC3: each mode reads its own steps (idea, design, raft, code, stream, final)" "AC3: design-challenge with a design record, the raft role against its own try's id, and final-review with an implementation fallback's record are true" "AC3: precedence live over rows over \`authorModel\` over the role's first choice; empty record or empty \`authorModel\` is none" "AC3: provenance is \`recorded\`, \`assumed\` or \`unknown\` as stated, and \`final\` is \`assumed\` when build alone is unrecorded"
}
check "AC3: \`authorship.of\` reads each mode's own steps (\`idea\`: idea; \`design\`: design; \`raft\`: raft; \`code\`, \`stream\`: build; \`final\`: idea, design, build), takes the writing role as an input (design-challenge, the raft role and final-review answer), applies live > rows > \`authorModel\` > first choice, and reports \`recorded\`, \`assumed\` or \`unknown\` as the Design states." ac3
ac4() {
	fixtureSpec authorship "AC4: a fallback attempt after a failed one, two layers on two models, and a draft and an answer on two models give every writer; a \`code-review\` or \`deliver\` row is no writer"
}
check "AC4: every writer of a step counts (a fallback after a failed attempt, several layers, a draft and its answer); a reviewer's or \`deliver\` row never does." ac4
ac5() {
	fixtureSpec authorread --run "AC5: the reader finds the rows in the item folders of the checkout it starts from (a dispatched review's author worktree and an interactive worktree), for an issue, a raft's members and a stream"
}
check "AC5: \`authorread.read\` finds the rows of the item folders of the checkout it starts from, for an issue, a raft's members and a stream." ac5
ac6() {
	fixtureSpec dispatch-env --run "AC6: each attempt's env carries \`ZN_MODEL\` = that attempt's model (a fallback's own); a nested review sets its own" && \
	fixtureSpec authorcmd --run "AC6: \`spend --phase prep|capture\` and \`commit\` take \`ZN_MODEL\` only for \`capture\`/\`prep\`/\`build\`; a typed \`--model\` wins; \`code-review\`/\`design-review\` rows take none"
}
check "AC6: the dispatcher sets \`ZN_MODEL\` to each attempt's \`spec.model\`; \`spend\`/\`commit\` take it only for \`capture\`, \`prep\` and \`build\`, a typed \`--model\` winning, and never for a reviewer's row." ac6
ac7() {
	fixtureSpec authorcmd "AC7: a marked item refuses prep/capture/build with no model; an unmarked item, other phases and a given \`--model\` are unchanged; the row and trailer hold the model"
}
check "AC7: in a marked item \`spend --phase capture|prep\` and \`commit --phase build\` refuse a missing model, naming \`--model\`; an unmarked item, other phases and a given model behave as today, and the row and trailer record the model." ac7
ac8() {
	fixtureSpec match "AC8: \`models.tries\` returns the same tries or error for every input, including a fallback author"
}
check "AC8: \`models.tries\` returns the same tries or the same error for every input as before." ac8
ac9() {
	fixtureSpec authorcmd "AC9: the restated skill and usage lines are pinned"
}
check "AC9: the restated skill and usage lines say what the Design states." ac9
check "AC10: the fast specs this change touches still pass." runFast

finish
