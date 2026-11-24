#!/usr/bin/env bash
# E3 (f0203 prep): with the prototype applied, in a throwaway clone (nothing outside it is written): type-check the
# acceptance specs as promoted (Lune definitions), format and lint them, and dry-run the promotion.
# Run from the top of a checkout, bounded: ./zn run --time 600 -- bash arcade/.tracker/issues/f0203/experiments/E3-types.sh
set -u
top=$(git rev-parse --show-toplevel)
d=$(mktemp -d "${TMPDIR:-/tmp}/f0203-e3.XXXXXX")
trap 'rm -rf "$d"' EXIT
git clone -q --no-hardlinks "$top" "$d/repo"
git -C "$d/repo" apply "$top/arcade/.tracker/issues/f0203/experiments/prototype.patch"
rm -rf "$d/repo/arcade/.tracker/issues/f0203/acceptance"
cp -R "$top/arcade/.tracker/issues/f0203/acceptance" "$d/repo/arcade/.tracker/issues/f0203/acceptance"
mkdir -p "$d/repo/arcade/tests/acceptance"
cp -R "$d/repo/arcade/.tracker/issues/f0203/acceptance" "$d/repo/arcade/tests/acceptance/f0203"
cd "$d/repo"
echo "== types (Lune definitions), promoted copy"
luau-lsp analyze --base-luaurc=.luaurc --platform=standard arcade/tests/acceptance/f0203 2>&1 | grep -E "acceptance/f0203.*Error" || echo "no type errors"
echo "== stylua, selene"
stylua --check arcade/.tracker/issues/f0203/acceptance && echo "formatted"
selene --quiet arcade/.tracker/issues/f0203/acceptance && echo "lint clean"
rm -rf arcade/tests/acceptance/f0203
echo "== promote-check (the clone)"
./zn promote-check f0203 2>&1 | grep -E "FAIL|TypeError|would break|ok|promot" | head -20
