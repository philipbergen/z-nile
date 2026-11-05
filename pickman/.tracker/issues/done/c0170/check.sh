#!/usr/bin/env bash
# Acceptance checks for c0170. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0170 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0170"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: tests/meta/tiers decides the helper tier's rule (tests/helper/<helper>/, loading only that helper, t and its own fixtures) and the unit tier's helper rule, on resolved files" lune run tests/run -- "$A/tiers.spec.luau"
check "AC2: R0059's plain.spec is in tests/helper/plain/ and passes, architecture.spec's tier case hands tiers the whole require graph and every helper and fails on a violation, and pickman-test names the tier" lune run tests/run -- "$A/layout.spec.luau"
check "AC3: the architecture rules hold on the tree" lune run tests/run -- tests/meta/architecture.spec.luau
check "AC4: zz-test and pickman-test list the helper tier and the plain helper among pickman's (checked at done; later work extends these lists)" bash -c 'z="$ZN_ROOT/z-nile/skills/zz-test/SKILL.md"; p="$ZN_ROOT/pickman/skills/pickman-test/SKILL.md"; grep -qF "pickman'"'"'s \`tests/unit\`, \`helper\`, \`contract\`" "$z" && grep -qF "its \`sim\`, \`place\`, \`fakeengine\` and \`plain\` helpers" "$z" && grep -qF "\`sim\`, \`place\`, \`fakeengine\` and \`plain\` are pickman'"'"'s." "$z" && grep -qF "its spec tiers (unit, helper, contract, integration, scenario, place, runtime)" "$p" && grep -qF "\`sim\`, \`place\`, \`fakeengine\` and \`plain\` are pickman'"'"'s helpers" "$p"' 
# AC5 names the tree's files below tests/ (sel adds the home and tests/): two of them (plain.luau, from R0059, and
# tiers.luau, this item's) do not exist until the work is done, so they are not literal paths for check-paths.
check "AC5: the selector picks a helper spec for its own change, and runs it (ALL, or a list holding it) for a change to its helper or the tier rule" bash -c 'h=pickman && sel() { (cd "$ZN_ROOT" && lune run "$ZN_ROOT/z-nile/affected" -- --project "$h" "$h/tests/$1"); } && s=helper/plain/plain.spec.luau && sel "$s" | grep -qxF "tests/$s" && for c in lib/plain.luau meta/tiers.luau; do o=$(sel "$c") && { echo "$o" | grep -qx ALL || echo "$o" | grep -qxF "tests/$s"; } || exit 1; done' 

finish
