#!/usr/bin/env bash
# Claude Code Stop hook: if tests/, z-nile/ or a project's home (pickman/, c0120) changed, the affected gate must pass
# before stopping.
export PATH="$HOME/.rokit/bin:$PATH"
input=$(cat)
# gate the tree the session is in (its repo root, even from a subdirectory); fall back to the hook's own repo
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
top=""
[[ -n $cwd ]] && top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || top=""
if [[ -n $top ]]; then cd "$top" || exit 0; else cd "$(dirname "$0")/../.."; fi
# Block at most once per stop attempt to avoid loops.
[[ $input == *'"stop_hook_active":true'* || $input == *'"stop_hook_active": true'* ]] && exit 0
# z-nile/ is the engine and the gate (c0114); every project root holds documents, which select no spec. A tree from
# before c0114 has no z-nile/roots.luau and no root under these folders. pickman/ is the game's home (c0120); src/ is
# its old place: a change there again is gated too, and the gate's old-roots check fails on it.
changed=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | grep -E '^(src|tests|z-nile|pickman)/' || true)
if [[ -f z-nile/roots.luau ]]; then
  while read -r root; do
    # a path under the root, by its prefix: tests/lib/tracker/x.luau is not under the root tracker
    [[ -n $root ]] && changed=$(printf '%s\n' "$changed" | awk -v r="$root/" 'index($0, r) != 1')
  done < <(lune run z-nile/roots 2>/dev/null)
fi
[[ -z ${changed//[[:space:]]/} ]] && exit 0
# scripts/check.sh is the gate in a tree from before c0114 and its forwarder after: this hook runs from the main
# checkout against any worktree, so it calls the path both have (design review 001 F2); the forwarder-removal raft
# switches it to z-nile/check.sh
if ! out=$(scripts/check.sh --affected 2>&1); then
  echo "scripts/check.sh --affected failed; fix before finishing:" >&2
  echo "$out" | grep -v -e '^\[INFO\]' -e '^\[WARN\]' | tail -n 40 >&2
  exit 2
fi
exit 0
