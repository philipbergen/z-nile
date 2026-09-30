#!/usr/bin/env bash
# Claude Code Stop hook: if src/ or tests/ changed, the affected gate must pass before stopping.
input=$(cat)
# gate the tree the session is in (its repo root, even from a subdirectory); fall back to the hook's own repo
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
top=""
[[ -n $cwd ]] && top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || top=""
if [[ -n $top ]]; then cd "$top" || exit 0; else cd "$(dirname "$0")/../.."; fi
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
