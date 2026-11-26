#!/usr/bin/env bash
# Acceptance checks for f0428. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0428 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0428"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"
# The specs share f0427's zn build helper and fixtures (a host, bare upstream, fork and tracker, a fake gh), all under .cache.
check "AC1: init clones the tracker, appends the exclude lines once, and is idempotent" lune run tests/run -- "$A/init.spec.luau"
check "AC2: init refuses a missing remote, a credential URL and unusual hosts, writing nothing" lune run tests/run -- "$A/init.spec.luau"
check "AC3: every host and tracker worktree resolves the one tracker" lune run tests/run -- "$A/resolve.spec.luau"
check "AC4: status clean in every worktree and the default branch unmoved after each command" lune run tests/run -- "$A/clean.spec.luau"
check "AC5: host refs and config change only as the Solution lists" bash -c "cd go && GOTOOLCHAIN=local go test ./internal/host -run TestSnapshotDelivery"
check "AC6: one branch per raft, layers per ticket, no tracker path, spend keys survive restack" lune run tests/run -- "$A/raftbranch.spec.luau"
check "AC7: zn pr pushes only to the fork, needs a person for a non-owned upstream, never merges" lune run tests/run -- "$A/pr.spec.luau"
check "AC8: the scan refuses local paths, tokens and keys in content, messages and names at commit and push" lune run tests/run -- "$A/scan.spec.luau"
check "AC9: a second machine with an ssh-form fork remote finds the project" lune run tests/run -- "$A/machine2.spec.luau"
check "AC10: recovery publishes landed once; a scan refusal is not retried" lune run tests/run -- "$A/recover.spec.luau"

finish
