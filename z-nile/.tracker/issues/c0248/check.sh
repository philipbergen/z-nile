#!/usr/bin/env bash
# Acceptance checks for c0248. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0248 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0248"

# A spec file holds the cases of several criteria; each case's label starts with its ACn. completion.spec is pure;
# layers-land.spec drives real git in a fixture under .cache (a local bare origin and a gh stub), one run per criterion
# that it covers, in order, as its cases build on each other; docs.spec reads the skills, templates and README.
check "AC1: a layer with no review in its issue folder is not complete (completion.layer)" lune run tests/run -- "$A/completion.spec.luau"
check "AC2: a layer whose newest review has no Verdict line, or a finding not answered by the final review's rules (one shared function), is not complete" lune run tests/run -- "$A/completion.spec.luau"
check "AC3: a layer is complete only when its review is current (its Commit, or its refute's, is the finish commit); a missing Commit line is not complete" lune run tests/run -- "$A/completion.spec.luau"
check "AC4: ./zn start opens the next layer only when the layer below is complete, and a review committed in the issue folder after finish keeps the layer finished" lune run tests/run -- "$A/layers-land.spec.luau"
check "AC5: ./zn done refuses a stack with any layer not complete, the top one included, and lands the same bind as before for a complete stack" lune run tests/run -- "$A/layers-land.spec.luau"
check "AC6: ./zn done <R> --through <issue> lands only the layers up to that issue's, after its own final review and trace, moves only those members, keeps the raft active and retargets the landed PRs and the next layer's to main" lune run tests/run -- "$A/layers-land.spec.luau"
check "AC7: ./zn done --through refuses a HEAD that is not that layer's published tip, an id that is not a member (or already landed), and an incomplete layer in the range" lune run tests/run -- "$A/layers-land.spec.luau"
check "AC8: after a --through landing stack shows landed, the next layer is stacked though the landed branch is gone from origin, and done lands the rest in a second bind that moves the raft" lune run tests/run -- "$A/layers-land.spec.luau"
check "AC9: every layer's PR body names the raft's Theme, its Order and the stack, refreshed by finish and done" lune run tests/run -- "$A/layers-land.spec.luau"
check "AC10: zz-execute, zz-rules, z-run and the prompt template say one worker builds the layers in order, each complete before the next, a second machine only through a takeover, and done --through below a block" lune run tests/run -- "$A/docs.spec.luau"
check "AC11: the README's Stacked delivery describes the one bind and is exists, its Roadmap row for c0248 is exists, c0248 to c0254 are one raft, and no merging bottom-up is left" lune run tests/run -- "$A/docs.spec.luau"
# every stack spec and promoted folder the change touches (the doc's Affected specs): the specs that exercise the stack
check "AC12: the stack specs (stack, stack-land, stack-fix, start-pr-reuse, trace, trace-land) and the promoted c0001, c0005, c0008, c0038, c0044, c0053, c0067, c0068, c0074, c0080, c0084, c0117, c0120 specs still pass" bash -c "specs=\$(for s in stack stack-land stack-fix start-pr-reuse trace trace-land; do echo tests/tooling/\$s.spec.luau; done; for c in c0001 c0005 c0008 c0038 c0044 c0053 c0067 c0068 c0074 c0080 c0084 c0117 c0120; do ls tests/acceptance/\$c/*.spec.luau; done) && [[ -n \$specs ]] && lune run tests/run -- \$specs"

finish
