#!/usr/bin/env bash
# c0115 design review 010 F1 and F2: rewrite-finished --check across the execution window, in a throwaway clone.
#   bash rewrite-finished-sim.sh <scratch dir outside the repository> <checkout to clone> <the base: c0120 done>
# Never run it in the repository: it commits, merges and moves refs, in the clone only.
set -u
S=$1/sim-clone
SRC=$2
BASE=$3
rm -rf "$S"
git clone -q --no-hardlinks "$SRC" "$S"
cd "$S" || exit 1
git config user.email sim@example.invalid; git config user.name sim
git checkout -q -b c0115
git update-ref refs/remotes/origin/main $BASE
RF=(lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished)
ck() { echo "--- $1"; out=$("${RF[@]}" -- --check 2>&1); code=$?; grep -v '^0 of' <<<"$out" | tail -4; echo "exit=$code"; }
ck "A: the branch against its base $BASE (expect 0)"
# 1: main edits finished files after the move
git checkout -q -b main-sim $BASE
echo "# a later reviewed comment" >> z-nile/.tracker/issues/done/c0004/check.sh
echo "# a later reviewed comment" >> z-nile/.tracker/rafts/done/R0025/check.sh
git commit -qam "main: edits two finished files"
git update-ref refs/remotes/origin/main HEAD
git checkout -q c0115 && git merge -q --no-edit main-sim
ck "1: main edited c0004 and R0025 after the move, merged (expect 0)"
# 2: an item finishes on main with an old path
git checkout -q main-sim
mkdir -p z-nile/.tracker/issues/done/c0199
printf '#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\ncheck "AC1: x" grep -q Worktrees ../.claude/skills/tracker/SKILL.md\nfinish\n' > z-nile/.tracker/issues/done/c0199/check.sh
git add -A && git commit -qm "main: c0199 finished with an old path"
git update-ref refs/remotes/origin/main HEAD
git checkout -q c0115 && git merge -q --no-edit main-sim
ck "2a: c0199 finished on main with an old path, merged (expect 1)"
"${RF[@]}" | tail -1
git commit -qam "c0115: rerun 5c after merging main"
ck "2b: after rerunning 5c as its own commit (expect 0)"
grep 'check "AC1' z-nile/.tracker/issues/done/c0199/check.sh
# 3: the branch deletes RC3 too
sed -i '' '/^check "RC3:/d' z-nile/.tracker/rafts/done/R0025/check.sh
git commit -qam "branch: RC3 deleted too"
ck "3: the branch deletes R0025's RC3 too (expect 1)"
git reset -q --hard HEAD~1
# F2: c0040 left as it was
git show $BASE:z-nile/.tracker/issues/done/c0040/check.sh > z-nile/.tracker/issues/done/c0040/check.sh
git commit -qam "branch: c0040 unrewritten"
ck "F2: c0040 left unrewritten (expect 1)"
git reset -q --hard HEAD~1
# 4: landed (squashed onto main), then a later main edit
tree=$(git rev-parse 'HEAD^{tree}')
landed=$(git commit-tree "$tree" -p main-sim -m "c0115 landed (squash)")
git checkout -q -B main-sim "$landed"
git update-ref refs/remotes/origin/main HEAD
ck "4a: landed, on main itself (expect 0, empty range)"
echo "# later" >> z-nile/.tracker/issues/done/c0007/check.sh
git commit -qam "main: a later edit to c0007" && git update-ref refs/remotes/origin/main HEAD
ck "4b: a later main edit after landing (expect 0)"
# 5: no origin/main
git checkout -q c0115
git update-ref -d refs/remotes/origin/main
ck "5: no origin/main (expect 1)"
