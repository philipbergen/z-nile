#!/usr/bin/env bash
# d0331 prototype runner. A standalone clone of the prep worktree in a fresh temp folder outside every checkout,
# origin removed; experiments/prototype.patch applied (skipped with PROTO=0, to see the specs fail on main);
# the issue's acceptance specs copied over; then the named specs run from z-nile's home. An optional MUTANT
# (a python script taking the clone's path) is applied after the patch. Writes nothing in the real repository.
# CHECK=1 runs ./zn check d0331 on the patched clone. GATE=1 runs z-nile's affected gate on the patched clone instead (no spec names).
# Usage: ./zn run --time 900 -- proto-run.sh <worktree> <spec name>...   (GATE=1: --time 3000)
set -euo pipefail
src="$1"; shift
issue="z-nile/.tracker/issues/d0331"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
case "$tmp/" in "$src/"*) echo "refusing: $tmp is inside $src"; exit 1 ;; esac
trap 'rm -rf "$tmp"' EXIT
git clone -q --no-hardlinks "$src" "$tmp/p"
cd "$tmp/p"
git remote remove origin
if [[ "${PROTO:-1}" == 1 ]]; then git apply "$src/$issue/experiments/prototype.patch"; fi
if [[ "${PROTO:-1}" == 1 ]]; then python3 "$src/$issue/experiments/apply-docs.py" "$tmp/p"; fi
if [[ -n "${MUTANT:-}" ]]; then python3 "$src/$issue/experiments/mutants.py" "$tmp/p" "$MUTANT"; fi
rm -rf "$issue/acceptance" && cp -R "$src/$issue/acceptance" "$issue/acceptance"
if [[ "${CHECK:-0}" == 1 ]]; then
  # the issue's own check.sh on the prototype
  cp "$src/$issue/check.sh" "$src/$issue/d0331.md" "$issue/"
  ./zn check d0331
  exit $?
fi
if [[ "${GATE:-0}" == 1 ]]; then
  # the affected gate on the prototype: the patch as one commit, selected against the commit below it
  git add -A
  git -c user.name=proto -c user.email=proto@example.invalid commit -q -m "d0331 prototype"
  bash z-nile/check.sh --affected --base HEAD~1 --project z-nile
  exit $?
fi
cd z-nile
specs=()
for name in "$@"; do specs+=(".tracker/issues/d0331/acceptance/$name.spec.luau"); done
if [[ "${TYPECHECK:-0}" == 1 ]]; then cd "$tmp/p" && ./zn promote-check d0331; exit $?; fi
lune run tests/run -- "${specs[@]}"
