#!/usr/bin/env bash
# Acceptance checks for c0261. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0261 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0261"

# A spec file holds the cases of several criteria; each label names what it is about. The exact model names are pinned
# only on the lines that set ZN_C0261_EXACT (check and `done`), never in the promoted specs the gate runs.
check "AC1: each activity has its own table in .models.toml, a closer file replaces only the keys it sets, and an unnamed review activity falls back to zz-review" lune run tests/run -- "$A/models-activities.spec.luau"
check "AC2: the final reviews obey the review rule (Opus on claude, grok at xhigh or Opus on agent), the rounds on the way take any model, a plain zz-review pin keeps c0117's rule" lune run tests/run -- "$A/models-activities.spec.luau"
check "AC3: a review round is its own activity, --final names the final round's, a stream is never final, the raft review is always final, every mode names its activity" lune run tests/run -- "$A/dispatch-activities.spec.luau"
check "AC4: z-wait is a model step whose poll is a loop with its own clock and exits 0, 2 and 3, and whose prompt runs only that command" lune run tests/run -- "$A/dispatch-activities.spec.luau"
check "AC5: a gate that only waits for green CI starts z-wait once per head, and never for a draft, a human's merge or the run gate" lune run tests/run -- "$A/dispatch-activities.spec.luau"
check "AC6: spend rows sum per model (ledger.byModel) and ./zn metrics prints the by-model table" lune run tests/run -- "$A/ledger-model.spec.luau"
check "AC7: the root .models.toml gives every activity a model on every CLI, finals above the rounds on the way, z-wait the cheapest, no alias, no tier vocabulary" lune run tests/run -- "$A/root-file.spec.luau"
check "AC8: the exact model of each activity on each CLI is the decided one" env ZN_C0261_EXACT=1 lune run tests/run -- "$A/root-file.spec.luau"
check "AC9: zz-rules, the review and authoring skills, AGENTS.md, the README and the .models.toml header say it per activity, with the final-round procedure" lune run tests/run -- "$A/docs.spec.luau"
check "AC10: ./zn dispatch zz-review starts the model of the activity (round cheap, --final expensive), refuses a final stream, and --dry-run names the activity" lune run tests/run -- "$A/dispatch-activities-cli.spec.luau"
# every promoted spec that reads .models.toml or the dispatcher, models or ledger modules (both alias spellings), except
# the cases this issue overrides (see Overrides: the executor rewrites them in its raft)
check "AC11: the promoted z-nile specs that name .models.toml, or require the dispatcher, models or ledger, still pass" bash -c "specs=\$(git grep -lE 'models\\.toml|(engine|scripts/tracker)/(dispatch|dispatcher|models|ledger)' -- tests/acceptance tests/tooling | grep '\\.spec\\.luau\$' | grep -v '/c0261/') && [[ -n \$specs ]] && lune run tests/run -- \$specs"

finish
