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
check "AC2: the final reviews obey the review rule (Opus on claude, grok at xhigh on grok, Opus first on agent with a kimi or grok-xhigh fallback, a fallback through agent only), the work on the way (a stream review, every other command) takes any model, a plain zz-review pin keeps c0117's rule" lune run tests/run -- "$A/models-activities.spec.luau"
check "AC3: every review mode names its activity (design, raft, final, code, stream), the design, raft, final and layer code reviews are bound by the review rule and a stream is not, and there is no --final" lune run tests/run -- "$A/dispatch-activities.spec.luau"
check "AC4: z-wait is a model step; its poll re-polls while checks are pending and exits 0, 2 or 3 (run against a fake gh), its prompt runs only that command, and a wait costs no lessons or skill read" lune run tests/run -- "$A/dispatch-activities.spec.luau" "$A/dispatch-activities-cli.spec.luau"
check "AC5: dispatch.next starts z-wait at a gate that only waits for its checks, once per head, and never for a draft, a conflict, a PR a human must judge, a gate left to a human or the run gate; the chain runs the step, stores waitedHead and merges when the PR turned green" lune run tests/run -- "$A/dispatch-activities.spec.luau" "$A/dispatch-wait-cli.spec.luau"
check "AC6: spend rows sum per model (ledger.byModel) and renderByModel prints the by-model table, and ./zn metrics prints it last" lune run tests/run -- "$A/ledger-model.spec.luau" "$A/metrics-model.spec.luau"
check "AC7: the root .models.toml gives every activity a model on every CLI, finals above the rounds on the way, z-wait the cheapest, no alias, no tier vocabulary" lune run tests/run -- "$A/root-file.spec.luau"
check "AC8: the exact model of each activity on each CLI is the decided one" env ZN_C0261_EXACT=1 lune run tests/run -- "$A/root-file.spec.luau"
check "AC9: zz-rules, the review and authoring skills, AGENTS.md, the README and the .models.toml header say it per activity: every review but a stream review is expensive, no round is counted and no --final exists" env ZN_C0261_EXACT=1 lune run tests/run -- "$A/docs.spec.luau"
check "AC10: ./zn dispatch zz-review starts the model of the activity (design review and layer code review expensive) and --dry-run names it; the dispatcher reads each CLI's model list once, starts kimi when agent lists no Opus and fails open on a failed list" lune run tests/run -- "$A/dispatch-activities-cli.spec.luau" "$A/dispatch-list-cli.spec.luau"
check "AC11: ./zn status <id> prepared refuses unless the design review round, and ./zn done unless the final review (final-review-NNN, not a layer's review-NNN), was recorded on a final-review KIND of model (any Opus, kimi k3.1-pro/k3-256k at high or max, grok at xhigh; matched by phase and exact subject; a raft's rounds carry the raft id in their subject; rows read from spend.md and spend.d), an issue with no design round is refused, items whose first review row predates the rule are not held to it, a typed --model wins over the measured one" lune run tests/run -- "$A/final-round.spec.luau" "$A/final-round-cli.spec.luau" "$A/final-round-raft.spec.luau" "$A/final-round-newraft.spec.luau" "$A/final-round-dispatch-raft.spec.luau" "$A/final-round-done.spec.luau" "$A/spend-model.spec.luau"
# every promoted spec that reads .models.toml or the dispatcher, models or ledger modules (both alias spellings), except
# the cases this issue overrides (see Overrides: the executor rewrites them in its raft)
check "AC12: the promoted z-nile specs that name .models.toml, a skill, the README or AGENTS.md, or require the dispatcher, models or ledger, still pass" bash -c "specs=\$(git grep -lE 'models\\.toml|(engine|scripts/tracker)/(dispatch|dispatcher|models|ledger)|AGENTS\\.md|SKILL\\.md|README\\.md|skills/|review-0' -- tests/acceptance tests/tooling | grep '\\.spec\\.luau\$' | grep -v '/c0261/') && [[ -n \$specs ]] && lune run tests/run -- \$specs"

finish
