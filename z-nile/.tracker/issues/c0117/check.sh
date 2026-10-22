#!/usr/bin/env bash
# Acceptance checks for c0117. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: the root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0117 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0117"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: .models.toml stacks key by key, a raft takes the stronger spec whole, three CLIs, nothing defaults, the review model is the CLI's" \
  lune run tests/run -- "$A/models.spec.luau"
check "AC2: script and model steps are classified, a model step's prompt names its files, and the chain stops at gates, questions and failures" \
  lune run tests/run -- "$A/dispatch.spec.luau"
check "AC3: one adapter per runtime starts its CLI headless and returns one token count and a quota signal" \
  lune run tests/run -- "$A/adapters.spec.luau"
check "AC4: the git and gh wrapper refuses a code push to main and an unauthorised merge" \
  lune run tests/run -- "$A/wrapper.spec.luau"
check "AC5: a spend row stores the model id beside its tokens, through spend --model and commit --model" \
  lune run tests/run -- "$A/ledger.spec.luau"
check "AC6: ./zn dispatch runs fake CLIs in order, falls through on quota only, kills at the cap, a stall and stop, records spend, stops at questions.md" \
  lune run tests/run -- "$A/dispatch-cli.spec.luau"
check "AC7: the skills, README, AGENTS.md, usage and prompt template say what the design says" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC8: the prompt names skill files and the architecture map (c0115 and c0120 specs, overridden), and the README spec stays green" \
  lune run tests/run -- tests/acceptance/c0115/prompt.spec.luau tests/acceptance/c0120/homes.spec.luau tests/acceptance/c0115/readme.spec.luau
check "AC9: the real tree's skill links, lessons and audit stay clean" \
  bash -c './zn skills --check && ./zn lessons --check && ./zn audit'
check "AC10: the dispatcher controls a run: questions, capture, a nested review, the broker, the tripwire and the watermark, the lifeline, the lock, stop, the call cap and the gates" \
  lune run tests/run -- "$A/control-cli.spec.luau"
check "AC11: one definition of tracker state (sequestered files judged per item, configuration never), and a broker that pushes only a fast-forward of it, commit by commit, bound to its run" \
  lune run tests/run -- "$A/trackerstate.spec.luau"
finish
