#!/usr/bin/env bash
# Acceptance checks for c0256. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home (z-nile/)
# sequestered specs: here before `./zn done`, promoted to the project's tests/acceptance/c0256 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0256"

check "AC1: the exchange names, renders, parses and orders messages; a loose date, a stray name, a gap, a repeat and a broken alternation are refused" lune run tests/run -- "$A/exchange.spec.luau"
check "AC2: a re-run's prompt names the exchange folder and every file in order, and a first run's prompt is unchanged" lune run tests/run -- "$A/exchange.spec.luau"
check "AC3: retry --answer/--answer-file stores the answer after the question, reruns the step, and refuses what it cannot take before anything moves" lune run tests/run -- "$A/retry.spec.luau"
check "AC4: any step is retried the same way, the re-run step reads the folder, a step that did not ask is told the history is others', and a review the author started is told to have the author ask" lune run tests/run -- "$A/step.spec.luau"
check "AC5: a capture keeps its words dated from the first message, stops as needs the user, is retried by name, and moves its exchange to its issue" lune run tests/run -- "$A/capture.spec.luau"
check "AC6: a second round appends, earlier messages stay byte for byte, and the third run is told about all of them" lune run tests/run -- "$A/rounds.spec.luau"

# AC7: the appended texts are claims about today's files (the paths are home-relative: z-design/check-paths-from-the-home),
# so they live here and not in a promoted case; after the raft's `done` this file is not rerun
has() { grep -qF -- "$2" "$1" || { echo "$1 does not say: $2"; return 1; }; }
docs_stand() {
  local rc=0
  has engine/main.luau '--answer "<text>" | --answer-file <path>' || rc=1
  has skills/zz-rules/SKILL.md '**Questions and answers** (c0256).' || rc=1
  has skills/zz-rules/SKILL.md 'A capture that stops with questions is retried as `retry new`, and its exchange moves to the issue it made.' || rc=1
  has README.md '`./zn dispatch retry <id> --answer <text>`' || rc=1
  return $rc
}
check "AC7: the help line, the zz-rules Dispatch section and the README name the answer input" docs_stand
check "AC8: the dispatcher's existing contracts hold (dispatch, docs, dispatch-texts, dispatch-guards)" lune run tests/run -- tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/docs.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/dispatch-guards.spec.luau

finish
