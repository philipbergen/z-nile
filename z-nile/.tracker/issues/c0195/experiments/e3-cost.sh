#!/usr/bin/env bash
# E3 (c0195): what does the fence's git add to one git call? 300 `git rev-parse HEAD` in a throwaway repository,
# the real git against the fence's git in front of it (a fixture: not protected, so the fast path).
# Usage: e3-cost.sh <prototype checkout> [<real git>]
set -u
P=${1:?prototype checkout}
T=$(mktemp -d "${TMPDIR:-/tmp}/c0195-e3.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
git init -q "$T/r" && cd "$T/r" && git -c user.email=a@x.test -c user.name=a commit -q --allow-empty -m x
real=${2:-$(command -v git)} # the git the fence would find first
export PICKMAN_FENCE_GIT=$real PICKMAN_FENCE_GIT_BUILTINS="$(git --list-cmds=builtins | tr '\n' ' ')" PICKMAN_FENCE_REAL_GIT=/nonexistent
shim="$P/z-nile/lib/git-hooks/bin/git"
for who in "$real" "$shim" "$real" "$shim"; do
  s=$(perl -MTime::HiRes=time -e 'print time')
  for _ in $(seq 300); do "$who" rev-parse HEAD >/dev/null; done
  e=$(perl -MTime::HiRes=time -e 'print time')
  perl -e "printf \"%-70s %.2f ms per call\n\", '$who', ($e-$s)*1000/300"
done
