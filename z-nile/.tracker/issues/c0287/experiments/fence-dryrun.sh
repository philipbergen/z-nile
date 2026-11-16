#!/usr/bin/env bash
# c0287 (design review 001 F1): repo-fence's guard scan with this item's whole folder where it sits before `done` and its
# acceptance/ folder where `done` promotes it (z-nile/tests/acceptance/c0287), in a clone of the prototype commit under a
# fresh `mktemp -d` outside every checkout (removed on any exit), against a control clone without them. Logs
# experiments/fence-dryrun-{control,promoted}.txt. Bounded by ./zn run:
#   ./zn run --time 900 -- bash <this file>
set -u
PROTO=0e79784e3
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
item=$(dirname "$here")
src=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir) || exit 2
t=$(mktemp -d "${TMPDIR:-/tmp}/c0287-fence.XXXXXX") || exit 2
t=$(cd "$t" && pwd -P)
case $t in */c0287-fence.*) ;; *) echo "fence-dryrun.sh: unexpected scratch path $t" >&2; exit 2 ;; esac
trap 'rm -rf "$t"' EXIT
trap 'exit 143' TERM INT HUP
if git -C "$(dirname "$t")" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "fence-dryrun.sh: $t is inside a checkout" >&2; exit 2
fi
clone() {
  git clone -q --shared --no-checkout "$src" "$t/$1" && git -C "$t/$1" checkout -q "$PROTO" && git -C "$t/$1" remote remove origin
}
clone control || exit 2
clone promoted || exit 2
dst="$t/promoted/z-nile/.tracker/issues/c0287"
rm -rf "$dst" && mkdir -p "$dst" && cp -R "$item"/. "$dst"/ || exit 2
mkdir -p "$t/promoted/z-nile/tests/acceptance/c0287" && cp -R "$item/acceptance"/. "$t/promoted/z-nile/tests/acceptance/c0287"/ || exit 2
for c in control promoted; do
  bash "$here/nostep.sh" "$t/$c" "$here/fence-dryrun-$c.txt" -- tests/tooling/repo-fence.spec.luau
  echo "$c exit=$?"
done
