#!/usr/bin/env bash
# Exit criteria for R0013. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0013); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0013

check "RC1: every finished item's check.sh (not closed:) lists its checks from an unrelated directory" bash -c '
  # without list mode this would run every done check.sh, raft ones included (the whole gate): refuse
  AC_LIST=1 bash -c "source scripts/lib/ac.sh; check probe false; finish" >/dev/null 2>&1 || { echo "ac.sh does not honour AC_LIST"; exit 1; }
  if AC_LIST=1 lune run tests/run -- tests/meta/architecture.spec.luau >/dev/null 2>&1; then echo "tests/run runs specs in list mode"; exit 1; fi
  here=$PWD
  for f in tracker/issues/done/*/check.sh tracker/rafts/done/*/check.sh; do
    dir=$(dirname "$f"); id=$(basename "$dir")
    if grep -q "^closed:" "$dir/$id.md"; then continue; fi
    out=$(cd /tmp && AC_LIST=1 bash "$here/$f" 2>&1) || { echo "$f:"; echo "$out" | tail -5; exit 1; }
    grep -q "criteria listed" <<<"$out" || { echo "$f printed no list summary"; exit 1; }
  done'
check "RC2: no skill describes the interim deferral form or the old done order" bash -c '
  if grep -rqF "interim form" .claude/skills; then echo "interim form still in the skills"; exit 1; fi
  if grep -qF "\`done\` pushes and then marks the PR ready" .claude/skills/tracker/SKILL.md; then echo "tracker skill: old order"; exit 1; fi
  if grep -qF "of the ready event" .claude/skills/tracker/SKILL.md; then echo "tracker skill: waits on the ready event"; exit 1; fi
  if grep -qF "pushes, and marks the PR ready" .claude/skills/execute-raft/SKILL.md; then echo "execute-raft: old order"; exit 1; fi'

finish
