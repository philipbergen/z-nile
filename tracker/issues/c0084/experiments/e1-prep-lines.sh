set -e; S=$1; rm -rf $S; mkdir -p $S; cd $S
# E1 (c0084 prep): `git diff --numstat origin/main...HEAD` over a prep's own paths is the same before and after
# the prep is squash-merged into main. Run: bash e1-prep-lines.sh <empty scratch dir outside every repository>
export GIT_AUTHOR_NAME=e1 GIT_AUTHOR_EMAIL=e1@example.invalid GIT_COMMITTER_NAME=e1 GIT_COMMITTER_EMAIL=e1@example.invalid
git init -q -b main seed; cd seed; mkdir -p tracker/issues/c0001; echo doc > tracker/issues/c0001/c0001.md; echo "#!/bin/sh" > tracker/issues/c0001/check.sh; git add -A; git commit -qm seed; cd ..
git clone -q --bare seed origin.git; git clone -q origin.git prep; git clone -q origin.git other
cd prep; git checkout -qb prep-x; mkdir -p tracker/issues/c0001/acceptance; printf 'a\nb\nc\n' > tracker/issues/c0001/acceptance/a.spec.luau; printf 'check 1\ncheck 2\n' >> tracker/issues/c0001/check.sh; echo more >> tracker/issues/c0001/c0001.md; git add -A; git commit -qm prep
cd ../other; echo x > other.txt; git add -A; git commit -qm other; git push -q origin main; cd ../prep
git fetch -q origin main; git merge -q --no-edit origin/main
P="tracker/issues/c0001/check.sh tracker/issues/c0001/acceptance tracker/issues/c0001/experiments"
echo "before merge:"; git diff --numstat origin/main...HEAD -- $P
git push -q origin prep-x
cd ../other; git fetch -q origin; git merge -q --squash origin/prep-x; git commit -qm "squash prep"; echo y > y.txt; git add -A; git commit -qm after; git push -q origin main; cd ../prep
git fetch -q origin main
echo "after squash merge:"; git diff --numstat origin/main...HEAD -- $P
echo "two-dot after merge:"; git diff --numstat origin/main HEAD -- $P; echo "(end)"
