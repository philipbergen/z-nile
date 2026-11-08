#!/usr/bin/env bash
# Acceptance checks for c0261. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0261 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0261"

# Work outside `check` is limited to running a spec through `tests/run`, `./zn members` and other cheap reads.
# A spec file holds the cases of several criteria; each label names the cases it is about, and a failing case of
# another criterion in the same file fails that file's checks too (the files are split by concern to keep that rare).
check "AC1: a per-skill table takes model, effort and rank from the tier it names, and a call can name the tier" lune run tests/run -- "$A/tiers-models.spec.luau"
check "AC2: a table that sets its own model keeps it, a file without tiers resolves as before, a closer file replaces only the keys it sets" lune run tests/run -- "$A/tiers-models.spec.luau"
check "AC3: tier errors name the file and the key, and a tier entry must be a real model name" lune run tests/run -- "$A/tiers-models.spec.luau"
check "AC4: the sharp tier is Opus on claude and grok at xhigh on grok and agent; the pin rule of a zz-review table stays" lune run tests/run -- "$A/tiers-models.spec.luau"
check "AC5: a review round runs cheap and only the final round, the idea review and the full-force review run sharp; a stream is never final" lune run tests/run -- "$A/dispatch-tiers.spec.luau"
check "AC6: authoring steps are cheap and no step that authors or orchestrates is sharp" lune run tests/run -- "$A/dispatch-tiers.spec.luau"
check "AC7: z-wait is a wait-tier model step with a bounded, one-condition poll command and a prompt that does nothing else" lune run tests/run -- "$A/dispatch-tiers.spec.luau"
check "AC8: spend records the tier beside the model in an eleventh column that older ledgers do without" lune run tests/run -- "$A/ledger-tier.spec.luau"
check "AC9: the root .models.toml defines cheap, sharp and wait for claude, grok and agent by the decided real names and ranks" lune run tests/run -- "$A/root-file.spec.luau"
check "AC10: every step's table references a tier and pins no model, and a final review resolves sharp where a middle round resolves cheap" lune run tests/run -- "$A/root-file.spec.luau"
check "AC11: every tier model is a real name, never an alias" lune run tests/run -- "$A/root-file.spec.luau"
check "AC12: zz-rules, the review and design skills, AGENTS.md, the README and the .models.toml header say it in tiers" lune run tests/run -- "$A/docs.spec.luau"
# every promoted spec that names .models.toml or reads the dispatcher's texts, except the cases this issue overrides
# (Overrides in the issue: the c0117 docs case about who reviews, rewritten by the executor in its raft)
check "AC13: the promoted z-nile specs that name .models.toml, the dispatcher or the ledger still pass" bash -c "specs=\$(git grep -lE 'models\\.toml|engine/(dispatch|dispatcher|models|ledger)' -- tests/acceptance tests/tooling | grep '\\.spec\\.luau\$' | grep -v '/c0261/') && [[ -n \$specs ]] && lune run tests/run -- \$specs"

finish
