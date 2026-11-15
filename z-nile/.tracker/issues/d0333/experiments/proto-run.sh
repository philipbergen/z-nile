#!/usr/bin/env bash
# builds a prototype clone with the fix (or MUTANT=<name>, or PROTO=0 for today's code), copies d0333's acceptance
# files into it and runs them (or the command given)
set -uo pipefail
SP=$1; W=$2; shift 2
P=$SP/d0333-proto
rm -rf "$P"
git clone -q --no-hardlinks "$W" "$P" || exit 2
cd "$P" && git remote remove origin && git checkout -q -B proto
[[ ${PROTO:-1} == 0 ]] || python3 -I "$(dirname "$0")/fix.py" "$P" ${MUTANT:-} || exit 2
stylua z-nile/engine/layergit.luau z-nile/engine/trace.luau
git diff > "$SP/d0333-last.patch"
git -c user.name=proto -c user.email=proto@example.invalid commit -qam proto --allow-empty
mkdir -p z-nile/.tracker/issues/d0333
cp -R "$W/z-nile/.tracker/issues/d0333/acceptance" z-nile/.tracker/issues/d0333/
cp "$W/z-nile/.tracker/issues/d0333/check.sh" z-nile/.tracker/issues/d0333/
cd z-nile
if [[ $# -gt 0 ]]; then "$@"; else lune run tests/run -- .tracker/issues/d0333/acceptance/post-finish.spec.luau .tracker/issues/d0333/acceptance/commit-land.spec.luau; fi
