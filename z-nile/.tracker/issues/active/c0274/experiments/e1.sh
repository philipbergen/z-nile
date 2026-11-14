#!/bin/bash
# E1 (c0274): atomic create + delete with leases against the real origin, well-formed probe names only.
set -u
cd /Users/philipbergen/code/pickman/.worktree/prep-take-over-lost-claim
A=refs/heads/hb/preparing-probe-alpha-zulu
B=refs/heads/hb/preparing-probe-bravo-zulu
git fetch -q origin main
tip=$(git rev-parse origin/main); tree=$(git rev-parse origin/main^{tree})
mk() { git commit-tree "$tree" -p "$tip" -m "hb $1 $2"; }
a1=$(mk preparing-probe-alpha-zulu 1); b1=$(mk preparing-probe-bravo-zulu 2)
echo "1 create A:"; git push -q --force-with-lease=$A: origin $a1:$A && echo ok
echo "2 swap with a WRONG lease on A (must reject whole push, B must not exist):"
git push -q --atomic --force-with-lease=$B: --force-with-lease=$A:0000000000000000000000000000000000000001 origin $b1:$B :$A 2>&1 | tail -2
git ls-remote --heads origin "refs/heads/hb/preparing-probe-*"
echo "3 swap with the RIGHT lease:"
git push -q --atomic --force-with-lease=$B: --force-with-lease=$A:$a1 origin $b1:$B :$A && echo ok
git ls-remote --heads origin "refs/heads/hb/preparing-probe-*"
echo "4 old owner beats A after the swap (lease on its old sha) must be rejected and A stay deleted:"
a2=$(mk preparing-probe-alpha-zulu 3)
git push -q --force-with-lease=$A:$a1 origin $a2:$A 2>&1 | tail -1
git ls-remote --heads origin "refs/heads/hb/preparing-probe-*"
echo "5 cleanup:"
git push -q origin :$B && echo deleted B
git ls-remote --heads origin "refs/heads/hb/preparing-probe-*"
