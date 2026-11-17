#!/usr/bin/env bash
# Acceptance checks for f0399. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0399 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0399"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# Each spec runs once (at the first criterion that names it, --run) and, when every case of the file passes, writes
# their names to a file (the runner records nothing for a file with a failing case);
# each criterion then checks its own cases. land and on are real-git fixtures; guesses, pick, plan and docs are pure.

OUTDIR="$PWD/.cache/f0399-check"
cases() {
	local spec="$1" home rel out c
	shift
	home="$(pwd -P)"
	rel="${A#"$home"/}/$spec.spec.luau" # the runner takes the spec's path from the project home
	out="$OUTDIR/$spec.txt"
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "$OUTDIR" && : >"$out" # an empty record when no case passes: each criterion then names its case
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$out" -- "$rel") || true
	fi
	[[ -f $out ]] || { echo "$spec.spec did not run"; return 1; }
	for c in "$@"; do
		grep -qxF "	$c" "$out" || { echo "did not pass: $c"; return 1; }
	done
}

check "AC1: \`guesses.luau\` parses and appends \`guesses.md\`, numbering from G1, refuses an unknown step, an empty field, a line break or a mark in a field, and a file that is not well formed, and tells a file that only gained guesses from one that lost or changed one." \
  cases guesses --run 'append numbers from G1 and parse reads back what was written' 'append refuses an unknown step, an empty field, a line break and a mark in a field' 'parse refuses a missing header, a gap in the numbers, an unknown step and a line that is not a guess' 'extends accepts added guesses and refuses a removed, changed or unreadable one'
check "AC2: the approval contract gains a \`guesses\` part only when \`guesses.md\` has text, an approval made before a guess no longer holds after it, and the changed part is named \`guesses\`." \
  cases guesses 'the contract has a guesses part only when guesses.md has text' 'an approval made before a guess no longer holds after it, and the changed part is guesses' 'a spec named guesses cannot be hashed'
check "AC3: \`openlist\` tells a bullet with a \`Guessed (agent, YYYY-MM-DD):\` line from one that waits, keeps \`pending\`'s meaning, and reads the guess and the issue a Guessed line names." \
  cases guesses 'a Guessed bullet is not waiting and is still pending' 'guessed reads the guess and the issue a Guessed line names, and skips a ruled bullet'
check "AC4: \`./zn work next\` with no raft named picks, among tickets with nothing unmet, a held raft that is ready to land, then a held raft to resume, then a raft to ready, then a raft or issue to fix, a prepared issue to raft, a design of this checkout to resume and an issue to design, lowest id first; it resumes held work only for a session that can be named and when no other live session carries it; and it never picks another checkout's design, an unchallenged idea, a closed or added issue." \
  cases pick --run 'with nothing unmet it lands a held approved raft, then readies, then rafts, then drafts' 'the lowest id wins inside one kind of pick' "it resumes this author's held raft that no live session carries, after one that only has to land and before a raft to ready" 'a held raft is not resumed when another session carries it, the session cannot be named, or another person holds it, and a stale carrier frees it' 'it never picks a held design of another checkout, an unchallenged idea, a closed issue, an added issue or a member' 'fix is offered for a raft ready refuses for a repairable reason and for a prepared issue with no size, and never for a dependency, questions or a changed approval' 'a design whose prep worktree is in this checkout is resumed before a new draft'
check "AC5: a ticket with an unmet dependency is picked only when no ticket without one has a pick, and only when its dependency is designed (to design or raft it) or is in one active raft with every layer finished (to build on it, as \`ready --on\`); a dependency on a closed issue is named as the person's." \
  cases pick 'a ticket with an unmet dependency is picked only when no ticket without one has a pick' 'tier 2 rafts or drafts a ticket only when every unmet dependency is designed' 'tier 2 readies a raft on the one active raft that holds its dependencies, once every layer there is finished'
# AC6 names cases of two specs: both run whatever the other's result (land.spec runs here, once, for every later criterion)
ac6() {
	local bad=0
	cases pick 'wait names each unapproved member once the gates have passed, and is not offered as a pick' 'an approved raft built on an unlanded raft waits for it, and lands once it has landed' 'a raft without lands goes to done as before, whatever its approvals' "an issue can be named: draft, a held design to resume, rafting, or its raft's action" "a project's folder sees only its own issues" "with no issue facts every pick is today's" 'the report lists the issues that were not picked under the head line' || bad=1
	cases land --run 'work next reads the issue facts: draft for a challenged issue, rafting for a prepared one, and wait for a built raft that is not approved' || bad=1
	return $bad
}
check "AC6: \`work next\` gives \`wait\`, naming each unapproved member, for a \`lands\` raft whose gates have passed, and for an approved raft built on an unlanded one; it accepts an issue id; an issue-level line reads \`<id>: <action> - <why>\`; and with no issue facts every pick is today's." \
  ac6
check "AC7: \`raftplan.plan\` puts a candidate in the raft of the candidate or open raft it depends on when they share type and project, past the cap, and keeps another type, another project and a solo issue apart." \
  cases plan --run 'two features with no shared surface share a raft when one depends on the other' 'a feature folds into the open raft that holds what it depends on' 'the cap never splits a chore from what it depends on, and still splits what is free' 'a dependent with a lower id than its dependency still joins it' 'another type, another project and a solo issue stay in their own rafts' 'a dependency that is not a candidate changes nothing'
check "AC8: \`./zn guess\` records a guess in the issue's \`guesses.md\` and refuses the main checkout, a bad step and an empty field; \`./zn guesses\` prints each member's guesses with its approval state, and \`--check\` fails on a malformed file." \
  cases land 'guess writes guesses.md, numbers the next one, commits nothing, and refuses the main checkout, a bad step and an empty field' "guesses prints each member's guesses with its approval state, and --check fails on a malformed file"
check "AC9: \`./zn ready\` accepts a raft whose members have no approval and records \`Lands: approved\` in its ready commit, leaving the raft document as it was; under \`ZN_DISPATCH\` it refuses as today and records nothing; it refuses an approved member whose design changed and accepts one whose guesses alone changed; and \`./zn finish\` on a \`lands\` raft goes on with a note naming the unapproved member." \
  cases land 'ready accepts a raft with an unapproved member and records Lands: approved in its ready commit, leaving the raft document as it was' 'ready under ZN_DISPATCH refuses a member with no approval and records nothing' 'ready refuses an approved member whose design changed and accepts one whose guesses alone changed' 'finish on a lands raft goes on and names the unapproved member'
check "AC10: \`./zn done\` on a \`lands\` raft lands nothing and names every member whose approval does not hold, whether it has none, gained a guess or had its design edited; \`./zn approve\` for an active issue runs only on the raft's top layer and pushes it, the layer is still finished, and \`done\` then lands the raft with the approval and the guesses in \`done/\`; a guess recorded after that approval makes \`done\` wait again, naming \`guesses\`; and a pushed guess that is removed is refused by \`finish\` and \`done\`." \
  cases land 'done on a lands raft lands nothing and names every member whose approval does not hold' 'a design edited on the layer after its approval makes done wait, naming design' 'a pushed guess that is removed is refused by finish and done' 'approve for an active issue runs only on the top layer and pushes it, the layer is still finished, and a later guess makes done wait again, naming guesses' 'done lands the raft once every approval holds, with approval.md and guesses.md in done/'
check "AC11: a raft whose ready commit has no \`Lands:\` trailer finishes and lands by today's approval rule." \
  cases land "a raft whose ready commit has no Lands: trailer finishes and lands by today's approval rule"
check "AC12: a Guessed bullet passes \`./zn status <id> prepared\`, \`./zn ready\` and \`./zn approve\` and still stops \`./zn status <id> preparing\` on an idea's bullet; a Guessed line naming no guess, or one that does not exist, is refused by \`status prepared\` and by \`ready\`." \
  cases land 'a Guessed bullet passes status prepared, ready and approve, and still stops status preparing' 'a Guessed line naming no guess, or one that does not exist, is refused by status prepared and by ready'
check "AC13: \`./zn ready <R> --on <D>\` readies a raft that depends on an unlanded active raft with finished layers, records \`On: <D>\` in its ready commit, and refuses a base that is not active, has an unfinished layer, does not hold every unmet dependency, or holds none." \
  cases on --run 'ready --on refuses a base that is not active, has an unfinished layer, does not hold every unmet dependency, or holds none' 'ready --on readies the raft and records On: and Lands: approved in its ready commit'
check "AC14: a raft readied \`--on <D>\` gets a base commit on \`<R>/base\` (\`D\`'s top layer plus its own folders as on \`main\`), starts its first layer on it as an active raft with its pull request based on that branch, cannot land before \`D\`, and after \`D\` lands \`./zn restack\` puts it on \`main\` with only its own commits and no backlog copy of its issues, and \`./zn done\` lands it." \
  cases on "start builds the base commit on the base's top layer with the raft's own folders as on main, cuts the first layer from it as an active raft, and stack says built on" 'done refuses while the base has not landed' 'after the base lands restack puts the raft on main with only its own commits and no backlog copy, and done lands it'
check "AC15: z-work, z-design, z-raft, z-ready, zz-execute, zz-review and zz-rules carry the guess-mode rules of section 7, AGENTS.md and the README say the worker designs and rafts on recorded guesses and lands nothing unapproved, and the four \"Headless\" sections are unchanged and identical." \
  cases docs --run 'z-work has Guess mode, the new actions, and no rule against guessing a human decision' 'z-design and z-raft have Guess mode before Headless' 'z-ready, zz-execute and zz-review say where approval is asked and that guesses are read' "zz-rules lists guess and guesses, the ready commit's trailers and where approval is checked" 'AGENTS.md and the README say the worker designs and rafts on recorded guesses' 'the four Headless sections are identical and still forbid guessing a ruling'
check "AC16: the usage text lists \`guess\`, \`guesses\`, \`ready <R-id|issue-id> [--on <R-id>]\` and the issue id for \`work\`." \
  cases land 'the usage text lists guess, guesses, ready --on and the issue id for work'
check "AC17: \`./zn approve <id> --publish\` publishes an approval of a backlog issue that has guesses." \
  cases land 'approve --publish publishes an approval of a backlog issue that has guesses'
check "AC18: \`./zn work next\` records the session that carries an item, and an unnamed call from another session does not resume it." \
  cases land 'work next records the session that carries an item, and an unnamed call from another session does not resume it'

finish
