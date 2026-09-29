#!/usr/bin/env bash
# Claude Code Stop hook: if src/ or tests/ changed, the affected gate must pass before stopping.
cd "$(dirname "$0")/../.."
input=$(cat)
# Block at most once per stop attempt to avoid loops.
[[ $input == *'"stop_hook_active":true'* || $input == *'"stop_hook_active": true'* ]] && exit 0
changed=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | grep -E '^(src|tests)/' || true)
[[ -z $changed ]] && exit 0
if ! out=$(scripts/check.sh --affected 2>&1); then
  echo "scripts/check.sh --affected failed; fix before finishing:" >&2
  echo "$out" | grep -v -e '^\[INFO\]' -e '^\[WARN\]' | tail -n 40 >&2
  exit 2
fi
exit 0
