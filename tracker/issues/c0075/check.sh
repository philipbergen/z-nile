#!/usr/bin/env bash
# Acceptance checks for c0075. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0075 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0075"

check "AC1: the Linux jail's command line is exactly the reviewed policy" lune run tests/run -- "$A/jail-argv.spec.luau"
check "AC2: a run that can't be jailed decides, refuses and explains as specified" lune run tests/run -- "$A/jail-verdict.spec.luau"
check "AC3: the lock is held by the launcher, and guarded processes record their pid only within its pid namespace" \
  lune run tests/run -- "$A/lock-pidns.spec.luau" "$A/launcher-lock.spec.luau"
check "AC4: scripts/linux-jail.sh installs, proves and (only with the flag) lifts the restriction" \
  lune run tests/run -- "$A/linux-jail-script.spec.luau"
check "AC5: in the run's real jail, a command through the fixture helper can't write the real checkout" \
  lune run tests/run -- "$A/live-jail.spec.luau"
check "AC6: CI, the fence's hooks and the documents know the Linux jail" lune run tests/run -- "$A/wiring.spec.luau"
# tests/run takes spec files, not folders
AC7=(tests/acceptance/c00{01,03,15,55,58,59,60,64,76,77,78,79}/*.spec.luau tests/tooling/{repo-fence,fence-cache-entry,fence-leftovers,sweeper-interlock,run-guard-relaunch}.spec.luau)
check "AC7: the existing fence, lock, jail, sweeper, workflow, setup and fixture specs pass" lune run tests/run -- "${AC7[@]}"

finish
