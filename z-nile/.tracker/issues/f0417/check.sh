#!/usr/bin/env bash
# Acceptance checks for f0417. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0417 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0417"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the round rule: caps 5, 9, 9; ended, answer, person, next, cap; who goes to the human; the window; the mark" lune run tests/run -- "$A/rounds.spec.luau"
check "AC2: a marked review is filed as the next round of its loop, from the dispatcher's own input; an unmarked folder keeps one round" lune run tests/run -- "$A/filing.spec.luau" "$A/rounds.spec.luau"
check "AC3: the idea loop's cap is rounds.CAP.idea, five" lune run tests/run -- "$A/idea.spec.luau"
check "AC4: work next runs the idea stage of a new ticket, after draft, in guess mode, and never guesses the person's words" lune run tests/run -- "$A/work.spec.luau" "$A/idea.spec.luau" "$A/capture.spec.luau" "$A/cli.spec.luau"
check "AC5: assumptions.md has one strict, append-only reader" lune run tests/run -- "$A/assumptions.spec.luau"
check "AC6: the approved contract names the idea (marked issues) and the assumptions, and older approvals keep their hash" lune run tests/run -- "$A/contract.spec.luau"
check "AC7: assume, assumptions, approve --check, the mark's writers, the claim's marks and its removal refused" lune run tests/run -- "$A/cli.spec.luau" "$A/marks.spec.luau"
check "AC8: a marked member lands only on-course, judged and approved on one contract, each problem with its kind" lune run tests/run -- "$A/lastgate.spec.luau"
check "AC9: a refusal goes back to rework through c0250's state, by the issue's state; refuse is a person's command" lune run tests/run -- "$A/lastgate.spec.luau" "$A/cli.spec.luau"
check "AC10: review-exhausted at the cap, and the loop's gate at status prepared" lune run tests/run -- "$A/lastgate.spec.luau" "$A/rounds.spec.luau" "$A/cli.spec.luau"
check "AC11: the skills say the loops, keep the pinned sentences and give c0161 its multi-round sentences" lune run tests/run -- "$A/docs.spec.luau"
check "AC12: a marked raft's code review is a loop of rounds per layer, in work next and in the layer's completion" lune run tests/run -- "$A/work.spec.luau" "$A/completion.spec.luau"
finish
