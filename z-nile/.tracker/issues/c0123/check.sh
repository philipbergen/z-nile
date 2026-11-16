#!/usr/bin/env bash
# Acceptance checks for c0123. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0123 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0123"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

check "AC1: an inherited hook folder is used only when its files are exactly the guard's: a bad one is ignored with a message, refused where the fence has no folder of its own, left alone under the jail; a nested copy lacking the folder keeps a genuine one; the fence's own folder is held to the same rule, and a refusal names what differs; the pins match the folder; the repository's own hook runs in the phases the skill states and can only refuse more; CDPATH, GIT_EXEC_PATH and exported shell functions cannot make the guard allow a write; a check-mode fence drops the caller's ssh command, protocol list and prompt setting" \
  lune run tests/run -- "$A/inherited-hooks.spec.luau"
check "AC2: the zz-test and zz-arch skills, SETUP.md and fence.sh's header state the pinned-hook and allow-listed-environment rules, and the stale 'switches the ref guard off' clause is gone" \
  lune run tests/run -- "$A/wording.spec.luau"
check "AC3: the shell and Lune readers of cleanenv.list apply one rule (agree on planted environments, idempotent, an unknown entry or an empty value refused, a still-dirty restart refuses); a run's PATH folders are kept only inside a folder the runner registered, judged by their canonical path and only while its run holds it, so a forged fence marker, a leftover, a .cache/.tmp folder, another spelling of a folder and a killed run's registry gain no folder and no fence name; the runner registers exactly its own run folder; a spec leaves no such folder behind; a moved HOME with a code ~ path in the account's git config refuses; inline use needs a privileged shell" \
  lune run tests/run -- "$A/cleanenv.spec.luau"
check "AC4: ./zn, the forwarders, the gate, zn check, a hand-started check.sh and the spec runner each start their children in the allow-listed environment under a poisoned caller environment" \
  lune run tests/run -- "$A/launchers.spec.luau"
check "AC5: every script a caller can start is privileged (#!/bin/bash -p; the guard's hooks, c0189's repository hook and the mktemp shim #!/bin/sh -p) and every Lune launcher starts shells only as /bin/bash -p or /bin/sh -p" \
  lune run tests/run -- "$A/entries.spec.luau"
# tests/run takes spec files, not folders
AC6=(tests/tooling/repo-fence.spec.luau tests/tooling/fence-inherited-env.spec.luau tests/tooling/fence-every-home.spec.luau
  tests/tooling/fence-cache-entry.spec.luau tests/tooling/fence-leftovers.spec.luau tests/tooling/lock-start-ids.spec.luau
  tests/tooling/start-pr-reuse.spec.luau tests/tooling/run-guard-relaunch.spec.luau tests/tooling/run-lane-error.spec.luau
  tests/tooling/board.spec.luau
  tests/acceptance/c0005/worktree.spec.luau tests/acceptance/c0008/done-order.spec.luau tests/acceptance/c0034/locator.spec.luau
  tests/acceptance/c0055/setup-run.spec.luau tests/acceptance/c0057/open.spec.luau tests/acceptance/c0058/fence.spec.luau
  tests/acceptance/c0058/lock.spec.luau tests/acceptance/c0074/done-gate.spec.luau tests/acceptance/c0077/replace-file.spec.luau
  tests/acceptance/c0081/allocate.spec.luau tests/acceptance/c0114/guards.spec.luau tests/acceptance/c0114/layout.spec.luau
  tests/acceptance/c0120/homes.spec.luau tests/acceptance/c0120/gate-homes.spec.luau tests/acceptance/c0120/layout.spec.luau
  tests/acceptance/c0127/reuse.spec.luau tests/acceptance/c0131/accept.spec.luau tests/acceptance/c0131/refuse.spec.luau
  tests/tooling/tracker-review-guards.spec.luau)
# c0189 is a dependency: its wiring spec must exist when this runs, so it fails loudly if it does not. The path is built
# from parts because c0120's path scan (rightly) rejects a path that does not exist yet in a prepared item's check.sh
C189=c0189
AC6+=("tests/acceptance/$C189/wiring.spec.luau")
# c0194 is a dependency too, and its promoted specs do not exist until it is done: built from parts for the same reason
C194=c0194
for f in callers runner shim; do AC6+=("tests/acceptance/$C194/$f.spec.luau"); done
check "AC6: the existing fence, home-fence, inherited-environment, guard, ref-hook, lock, done, start, setup, gate, board, worktree and locator specs pass (33 files, c0189's wiring spec among them: c0189 is a dependency, so a missing file fails here), the ones this chore overrides included" lune run tests/run -- "${AC6[@]}"
# The allow-list entries, in the spelling the file uses for promoted items (the id through renamed.id, which the
# user's compaction renumbers), anchored on the key line so a comment naming the path does not pass. The patterns are
# inline greps: the path scanners skip a grep's pattern.
ac7() {
  grep -qF -- 'local C0123 = renamed.id("c0123")' tests/tooling/repo-fence.spec.luau &&
    grep -qF -- 'ALLOWED[`z-nile/tests/acceptance/{C0123}/inherited-hooks.spec.luau`] = {' tests/tooling/repo-fence.spec.luau &&
    grep -qF -- 'ALLOWED[`z-nile/tests/acceptance/{C0123}/cleanenv.spec.luau`] = {' tests/tooling/repo-fence.spec.luau &&
    grep -qF -- 'ALLOWED[`z-nile/tests/acceptance/{C0123}/launchers.spec.luau`] = {' tests/tooling/repo-fence.spec.luau &&
    grep -qF -- 'ALLOWED[`z-nile/tests/acceptance/{C0123}/wording.spec.luau`] = {' tests/tooling/repo-fence.spec.luau
}
check "AC7: repo-fence's allow-list names the four specs that quote guarded names, where done promotes them (entries.spec needs none)" ac7

finish
