#!/usr/bin/env bash
# Acceptance checks for c0275. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0275 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0275"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure rules: the one lease (the sha this checkout last wrote, else the sha seen, else create-only); a throttle mark is its stamp, epoch and sha and anything else is no mark; a beat is due when none was made, an interval has passed or the mark is dated past the skew allowance; a failed attempt advances the mark and keeps the sha it knew; a claim starts its background beater unless the dispatcher beats, it is the main checkout, a check protects it or one runs; its command; whether it runs; its session; what ends the watch loop; the dispatcher's stamp and the child's answer; and the reaper spares a beater and what runs below it" lune run tests/run -- "$A/plan.spec.luau" "$A/reap.spec.luau"
check "AC2: every claim publish gives the first beat and, in a worktree, the mark; any ./zn command in a worktree beats once an interval has passed (none inside it, no network call, leasing on the sha it wrote); nothing beats from a protected checkout; a failed first beat does not fail the claim and is not retried inside the interval; a claim given back or taken over elsewhere is dropped with one word, once; a give-back, release and stop (after its verdict) drop the heartbeat branch; a claim held in a worktree starts its beater once and again after it ended, and a headless step, a spec and the main checkout start none; a takeover's taker beats its own branch" lune run tests/run -- "$A/autobeat.spec.luau"
check "AC3: (the proofs are pinned by hash, so a changed proof fails here) the real beater outlives the command that started it, beats while no command runs and ends with its worktree, its memory, its claim or its session; a long check beats while it runs; a hung remote is bounded and not retried inside the interval; the dispatcher beats while a step works" bash -c '[[ ! -d "$0/acceptance" ]] || { [[ $(git hash-object "$0/proofs/beater.spec.luau") == fcafc1510deaedc8fee0c2e271214ad28e972cba ]] || { echo "proofs/beater.spec.luau changed since it was pinned" >&2; exit 1; }; [[ $(git hash-object "$0/proofs/long.spec.luau") == 232ec2f829fb08364454a92140633c3e63f23112 ]] || { echo "proofs/long.spec.luau changed since it was pinned" >&2; exit 1; }; [[ $(git hash-object "$0/proofs/dispatch.spec.luau") == 809be03b045cc80be43c0890a75f0c6db1e6f926 ]] || { echo "proofs/dispatch.spec.luau changed since it was pinned" >&2; exit 1; }; lune run tests/run -- "$0/proofs/beater.spec.luau" "$0/proofs/long.spec.luau" "$0/proofs/dispatch.spec.luau"; }' "$HERE"
check "AC4: zz-rules names the automatic beats, the four skills say the claim keeps itself alive and keep ./zn beat and --time 3600, zz-test says the reaper spares a beater and a session end stops the beaters tied to it, and the README roadmap has the c0275 row" bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  R="$ZN_ROOT/z-nile"
  for w in "Automatic beats" "tracker-beats" "Background beater"; do g "$w" "$R/skills/zz-rules/SKILL.md"; done
  for s in z-design z-raft z-run zz-execute; do g "keeps itself alive" "$R/skills/$s/SKILL.md"; g "./zn beat" "$R/skills/$s/SKILL.md"; g "--time 3600" "$R/skills/$s/SKILL.md"; done
  g "the ending session" "$R/skills/zz-test/SKILL.md"
  grep -qE "^\| .* \| c0275 \| exists \|" "$R/README.md" || { echo "README roadmap has no c0275 exists row" >&2; exit 1; }
'

finish
