#!/usr/bin/env bash
# c0302 AC2: the seven fixture specs give the same results when the checkout they clone is on a stack layer branch as
# on a plain branch. A real-work proof, run once from check.sh and never from a promoted spec: all seven are in
# tests/slow.tsv, so no gate runs them (z-design/guards-name-slow-tier-specs), and they are what this issue changes.
# Measured in prep: about 65 s for the two runs (33 s and 32 s), one clone of the repository plus one per spec per run.
#
# It works on a copy, never the checkout: a fresh `mktemp -d` outside the repository (zz-test, Writers: a whole tree
# is never built at a fixed name under .cache), removed by a trap on every exit. It clones the checkout there with
# --no-hardlinks, copies the working tree's seven specs over the clone's, removes the clone's origin, and runs the
# seven twice in the clone: on R9999/1/c9999 with no other branch, then on a plain branch.
#
# The clone's runner gets none of a dispatched step's environment (d0298 owns that leak for spec runs in general:
# until it lands, c0008/done-order fails one case under ZN_DISPATCH=1 with z-nile/bin first on PATH, whatever this
# issue changes), so this proof gives the same answer interactive and headless.
# Usage: bash layer.sh (from anywhere inside the checkout).
set -uo pipefail
top=$(git rev-parse --show-toplevel) || exit 2
SPECS=(
  tests/acceptance/c0001/tracker-lifecycle.spec.luau
  tests/acceptance/c0008/done-order.spec.luau
  tests/acceptance/c0038/deferred.spec.luau
  tests/acceptance/c0050/start-depends.spec.luau
  tests/acceptance/c0074/done-gate.spec.luau
  tests/acceptance/c0080/consequences.spec.luau
  tests/acceptance/c0120/promote-home.spec.luau
)
hold=$(mktemp -d "${TMPDIR:-/tmp}/c0302-layer.XXXXXX") || exit 2
trap 'rm -rf "$hold"' EXIT
dir="$hold/repo"
git clone -q --no-hardlinks "$top" "$dir" || { echo "clone failed"; exit 1; }
# the clone, never the real checkout: every git command below names it, and it is checked to be its own checkout
[[ $(cd "$dir" && git rev-parse --show-toplevel) -ef $dir && ! $dir -ef $top ]] || { echo "refused: $dir is not its own checkout"; exit 2; }
for s in "${SPECS[@]}"; do cp "$top/z-nile/$s" "$dir/z-nile/$s" || exit 1; done
git -C "$dir" remote remove origin || exit 1 # the clone stands alone: nothing in it names the real checkout

# PATH without any z-nile/bin (a dispatched step puts its git and gh wrappers first)
path=""
IFS=: read -ra parts <<<"$PATH"
for p in "${parts[@]}"; do
  [[ $p == */z-nile/bin ]] || path="${path:+$path:}$p"
done
seven() { # runs the seven in the clone, outside a dispatched step's environment
  (cd "$dir/z-nile" && env -u ZN_DISPATCH -u ZN_HEADLESS -u ZN_DISPATCH_DIR -u ZN_DISPATCH_HOME \
    -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_DISPATCHER_PID -u ZN_REAL_GIT -u ZN_REAL_GH \
    -u GH_TOKEN -u GITHUB_TOKEN -u ZN_AGENT_GH_TOKEN PATH="$path" lune run tests/run -- "${SPECS[@]}")
}
only() { # the clone's local branches must be exactly the one named
  [[ $(git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads) == "$1" ]] || { echo "the clone's branches are not just $1"; return 1; }
}
rc=0
was=$(git -C "$dir" branch --show-current)
git -C "$dir" checkout -q -B R9999/1/c9999 || exit 1
[[ -z $was || $was == R9999/1/c9999 ]] || git -C "$dir" branch -q -D "$was" || exit 1
only R9999/1/c9999 || exit 1
echo "== on the layer branch R9999/1/c9999"
seven || rc=1
git -C "$dir" checkout -q -B c0302-plain || exit 1
git -C "$dir" branch -q -D R9999/1/c9999 || exit 1
only c0302-plain || exit 1
echo "== on the plain branch c0302-plain"
seven || rc=1
exit $rc
