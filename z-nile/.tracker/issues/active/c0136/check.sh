#!/usr/bin/env bash
# Acceptance checks for c0136. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0136 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0136"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The promoted specs pin the rules; the exact sentences of the skills and AGENTS.md live here, where they run at done
# and never again (they are grep patterns written inline, none starting with "(").

check "AC1: a harvest entry and a note read an optional (erred …) group, a finding's Erred and Upstream lines parse by the same rules, malformed ones are refused, and the ledger reader sees ids behind a group" \
	lune run tests/run -- "$A/parse.spec.luau"
check "AC2: lessons --check refuses a lesson filed under a step the line does not name, a step that is no skill, a line the reviewer contradicts, a build-only lesson for a design step or a design review finding, and a half-filled review (a review whose lines cannot be read binds nothing, and a waiver note clears it)" \
	lune run tests/run -- "$A/check.spec.luau"
check "AC3: ./zn lessons --unattributed [<id>...] lists the entries that name no step (exit 1), passes when none (exit 0), and refuses mixed options (exit 2); --check-review <path> reads one new review anywhere, read-only, and refuses unreadable lines, a finding with no lines and a focused heading with no phase" \
	lune run tests/run -- "$A/cli.spec.luau"
check "AC4: stream and focused reviews are harvest sources, uncovered like a design or code round, and a focused review is not an item's document" \
	lune run tests/run -- "$A/sources.spec.luau"
ac5() {
	lune run tests/run -- "$A/docs.spec.luau" || return 1
	local f
	for f in "$ZN_ROOT"/z-nile/skills/*/SKILL.md "$ZN_ROOT"/pickman/skills/*/SKILL.md; do
		grep -qF -- "A lesson goes to the step that erred: the skill whose instructions the author was following when the mistake was made, or the skill of an earlier step that should have prevented or caught it (that skill is \`<the skill the lesson improves>\` below). The harvest line names that step as \`(erred <skill>[, upstream <skill>])\` before its colon (zz-rules skill, Items), and every kind of review and correction is harvested: a finding of a design, code, stream or focused review as an entry of the item's \`harvest.md\`, and a programme review, a correction by the user or a failed step as a \`- note\` entry." "$f" ||
			{ echo "no lead-in paragraph in $f"; return 1; }
	done
	grep -qF -- "z-design, z-raft and zz-execute harvest every review finding into them (the lead of a prep or raft also each stream and focused review), each under the step that erred (\`(erred <skill>)\` on its harvest line; zz-rules skill, Items)." "$ZN_ROOT/AGENTS.md" &&
		grep -qF -- "Ask: which step made this mistake, and which earlier step should have caught it?" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "## Focused mode (any review outside a design or code round)" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "Every finding of a design review is a mistake made in design (or in the capture it was given)" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "In code mode, when the mistake sits in something design wrote (the issue document, \`check.sh\`, a sequestered spec, a prototype it copied), \`Upstream:\` names \`z-design\`." "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "(folder: zz-rules skill, Items)" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "\`Erred: zz-review\` is for an earlier round's own mistake (a wrong finding or recommendation); a mistake an earlier round missed names the step that made it, with \`Upstream: zz-review\`." "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "in the folder of the \`harvest.md\` its lead writes in: the issue's during prep, the raft's during a raft's execution, whatever item it concerns" "$ZN_ROOT/z-nile/skills/zz-rules/SKILL.md" &&
		grep -qF -- "a candidate lesson of a report as \`- note ws-<issue> (erred <skill>): <lesson ids>\`" "$ZN_ROOT/z-nile/skills/zz-execute/SKILL.md" &&
		grep -qF -- "only a lesson filed under \`zz-review\` for the reviewer's own mistake is exempt" "$ZN_ROOT/z-nile/skills/z-design/SKILL.md" &&
		grep -qF -- "A round with no step lines at all is not finished: the author sends it back to you" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "or from a finding of a design-phase review (a design round, or a focused review whose heading says design) except a lesson filed under \`zz-review\` for the reviewer's own mistake, must be \`design\` or \`both\`" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "a new round without them goes back to its reviewer before you commit or harvest it: run \`./zn lessons --check-review <the round's file>\` on every round you receive, and a failure sends it back." "$ZN_ROOT/z-nile/skills/z-design/SKILL.md" &&
		grep -qF -- "run \`./zn lessons --check-review <the round's file>\` on each new review round, and a round that fails, or has no step lines, goes back to its reviewer" "$ZN_ROOT/z-nile/skills/zz-execute/SKILL.md" &&
		grep -qF -- "\`./zn lessons --check-review\` refuses a file that has findings and no step lines" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "the issue's during prep and the raft's during a raft's execution whatever item the review concerns" "$ZN_ROOT/z-nile/skills/zz-review/SKILL.md" &&
		grep -qF -- "\`--tags\`, \`--check\`, \`--check-review <path>\`, \`--uncovered [<id>...]\`, \`--unattributed [<id>...]\` | read-only." "$ZN_ROOT/z-nile/skills/zz-rules/SKILL.md" &&
		grep -qF -- "Then \`./zn lessons --uncovered <id>\`, \`./zn lessons --unattributed <id>\` and \`./zn lessons --check\` must all pass." "$ZN_ROOT/z-nile/skills/z-design/SKILL.md" &&
		grep -qF -- "Then \`./zn lessons --uncovered R0010\`, \`./zn lessons --unattributed R0010\` and \`./zn lessons --check\` must pass." "$ZN_ROOT/z-nile/skills/zz-execute/SKILL.md" &&
		grep -qF -- "\`./zn lessons --uncovered <R-id>\`, \`./zn lessons --unattributed <R-id>\` and \`./zn lessons --check\`" "$ZN_ROOT/z-nile/skills/z-raft/SKILL.md"
}
check "AC5: every skill carries the lead-in paragraph, and zz-review, zz-rules, z-design, z-raft, zz-execute and AGENTS.md carry the exact sentences that name the step, the focused mode and the command" ac5
ac6() {
	"$ZN_ROOT/zn" lessons --check | grep -q ", ok$" || { echo "lessons --check is not ok on this tree"; return 1; }
	# the 19 stream reviews already on main are harvest sources now: uncovered lists their findings (c0112 backfills them)
	"$ZN_ROOT/zn" lessons --uncovered | grep -q " stream-review-" || { echo "uncovered lists no stream review"; return 1; }
	local s
	for s in harvest lessons-cli skill-docs; do
		lune run tests/run -- "tests/acceptance/c0111/$s.spec.luau" || return 1
	done
}
check "AC6: every existing harvest entry still reads (lessons --check is ok on this tree), the stream reviews on main are uncovered sources, and the three c0111 specs this chore overrides pass" ac6

check "AC7: renumber (like compact and remap) moves a stream review's and refute's files with the id its harvest entry names, tracked or not, and leaves another issue's alone" \
	lune run tests/run -- "$A/renumber-streams.spec.luau"

finish
