#!/usr/bin/env bash
# Acceptance checks for c0264. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0264 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0264"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

# The section's text, word for word. It lives here, in the sequestered check.sh, so the executor cannot change what it is
# held to; no promoted spec pins it, so later bullets need no override.
read -r -d '' INTENT <<'TXT'
## Intent
z-nile is built so that people spend their time on ideas and designs, and workers do the rest, cheaply until the last step and sharply at it.
- **Humans at the idea and the design.** A person has the idea, settles what is asked and approves the design: `z-ticket` captures it, `z-design` sharpens it into a prepared issue and its design review. Nothing is designed past a person's ask.
- **Workers from the raft to the merge.** Workers carry a prepared issue's raft to its merge: raft, ready, run, review, gate, merge. They stop and escalate only when blocked (Escalation to the human), and a person comes back only for that.
- **Cheap on the way, sharp at the end.** The steps on the way run on cheap models; the final review, the one that decides whether the work merges, runs on the sharpest model. Rigor does not move: the checks, the gate and the review rounds still run.

This section is the aim and carries no status label. How it should work, below, labels each part as exists, designed or captured; where its plans have a worker design, how they meet this aim is the user's open question.
TXT
verbatim() {
	local got
	got="$(awk '/^## Intent$/{on=1} /^## How it should work$/{on=0} on' "$ROOT/z-nile/README.md")"
	[[ "$got" == "$INTENT" ]] || { echo "the Intent section differs from the Design's text:"; diff <(printf '%s\n' "$INTENT") <(printf '%s\n' "$got"); return 1; }
}

check "AC1: '## Intent' is the first '##' section and '## How it should work' follows it at once" lune run tests/run -- "$A/intent-ac1.spec.luau"
check "AC2: the section states the three halves of the intent" lune run tests/run -- "$A/intent-ac2.spec.luau"
check "AC3: the section is a plain aim with no state label" lune run tests/run -- "$A/intent-ac3.spec.luau"
check "AC4: the section is the Design's text, word for word" verbatim
check "AC5: the specs that read the README still pass" lune run tests/run -- \
	tests/acceptance/c0259/readme.spec.luau tests/acceptance/c0115/readme.spec.luau tests/acceptance/c0115/docs.spec.luau \
	tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0183/docs.spec.luau \
	tests/acceptance/c0184/docs.spec.luau tests/acceptance/c0185/docs.spec.luau \
	tests/acceptance/c0082/audit.spec.luau tests/acceptance/c0115/layout.spec.luau tests/acceptance/c0120/graph-homes.spec.luau tests/acceptance/c0185/graph.spec.luau

finish
