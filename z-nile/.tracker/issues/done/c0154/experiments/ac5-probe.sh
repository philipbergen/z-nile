#!/usr/bin/env bash
# c0154 design review 003 F1: AC5's promoted_unchanged is red when git can't compare (no origin/main), green with no
# change, red when a promoted spec changes. Run against a scratch clone only: bash ac5-probe.sh <scratch dir>
set -u
dir=${1:?usage: ac5-probe.sh <scratch dir>}
check=$(cd "$(dirname "$0")/.." && pwd -P)/check.sh
fn=$(sed -n '/^promoted_unchanged() {/,/^}/p' "$check")
rm -rf "$dir" && mkdir -p "$dir" && cd "$dir" || exit 2
git init -q -b main origin.git --bare && git clone -q origin.git work 2>/dev/null && cd work || exit 2
git config user.name c0154 && git config user.email c0154@example.invalid
mkdir -p pickman/tests/acceptance/f1 z-nile/tests/acceptance/c1 && echo a > pickman/tests/acceptance/f1/a.spec.luau && echo b > z-nile/tests/acceptance/c1/b.spec.luau
git add -A && git commit -qm seed && git push -q origin main && git fetch -q
ZN_ROOT=$PWD; eval "$fn"
promoted_unchanged >/dev/null && echo "green with no change: ok" || echo "green with no change: FAILED"
echo changed >> pickman/tests/acceptance/f1/a.spec.luau && git commit -qam change
promoted_unchanged >/dev/null && echo "red on a changed promoted spec: FAILED" || echo "red on a changed promoted spec: ok"
git reset -q --hard HEAD~1
git update-ref -d refs/remotes/origin/main
promoted_unchanged >/dev/null && echo "red without origin/main: FAILED" || echo "red without origin/main: ok"
