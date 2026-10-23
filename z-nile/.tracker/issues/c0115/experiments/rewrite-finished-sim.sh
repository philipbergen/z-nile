#!/usr/bin/env bash
# c0115 design reviews 010 and 011: rewrite-finished --check (AC14) and AC13 across the execution window, in throwaway
# clones whose origin is a local bare repository (main's tip is read from it with ls-remote, design review 011 F1).
#   bash rewrite-finished-sim.sh <scratch dir outside the repository> <checkout to clone> <the base: c0120 done>
# Never run it in the repository: it commits, merges, pushes and moves refs, in the scratch clones only.
set -u
S=$1/sim
SRC=$2
BASE=$3
rm -rf "$S"
mkdir -p "$S"
git clone -q --no-hardlinks "$SRC" "$S/b"
git -C "$S/b" branch -q -f main "$BASE"
git clone -q --bare --no-hardlinks "$S/b" "$S/origin.git"
git -C "$S/origin.git" branch -q -f main "$BASE"
git clone -q "$S/origin.git" "$S/branch" # the c0115 branch
git clone -q "$S/origin.git" "$S/main"   # main's own later work
for d in branch main; do git -C "$S/$d" config user.email sim@example.invalid; git -C "$S/$d" config user.name sim; done
B=$S/branch
cd "$B" || exit 1
git checkout -q -b c0115 "$(git -C "$SRC" rev-parse HEAD)" 2>/dev/null || { git fetch -q "$SRC" HEAD && git checkout -q -b c0115 FETCH_HEAD; }
RF=(lune run z-nile/.tracker/issues/c0115/experiments/rewrite-finished)
ck() {
  local out code
  out=$("${RF[@]}" -- --check 2>&1); code=$?
  echo "--- $1: exit=$code (expect $2) :: $(grep -v -e '^0 of' -e 'compared with' -e 'each still at HEAD' <<<"$out" | head -3 | tr '\n' '|')"
}
mainwork() { # mainwork <message> <command…>: a commit on main, pushed, then fetched by the branch clone
  local msg=$1; shift
  (cd "$S/main" && git fetch -q && git checkout -q -B main origin/main && "$@" && git add -A && git commit -qm "$msg" && git push -q origin main)
  git fetch -q origin
}
merge_main() { git merge -q --no-edit origin/main; }

ck "honest: the branch against its base" 0
# 011 F1: a forged local ref is never read
sed -i '' 's/^check "AC1: .*/check "AC1: weakened" true/' z-nile/.tracker/issues/done/c0004/check.sh
git commit -qam "branch: c0004 AC1 weakened"
ck "the branch weakens c0004 AC1" 1
git update-ref refs/remotes/origin/main HEAD
ck "...and forges refs/remotes/origin/main to HEAD" 1
git commit -q --allow-empty -m "one more"
git update-ref refs/remotes/origin/main HEAD~1
ck "...and forges it to the edit commit, one commit on" 1
git reset -q --hard HEAD~2
git fetch -q origin
# 011 F1: the remote not fetched, and the remote unreachable
(cd "$S/main" && git fetch -q && git checkout -q -B main origin/main && git commit -q --allow-empty -m "main moves" && git push -q origin main)
ck "origin's main moved and isn't fetched" 1
git fetch -q origin && merge_main
ck "after fetching and merging it" 0
git remote set-url origin "$S/nowhere.git"
ck "origin unreachable" 1
git remote set-url origin "$S/origin.git"
# 011 F2: a finished file the branch deletes, renames or moves
git rm -q z-nile/.tracker/issues/done/c0004/check.sh && git commit -qm "branch: c0004's check.sh deleted"
ck "B: the branch deletes c0004/check.sh" 1
git reset -q --hard HEAD~1
git mv z-nile/.tracker/issues/done/c0006 z-nile/.tracker/issues/done/c0206
sed -i '' '/^check "AC1:/d' z-nile/.tracker/issues/done/c0206/check.sh && echo 'check "AC9: any" true' >> z-nile/.tracker/issues/done/c0206/check.sh
git add -A && git commit -qm "branch: c0006 renamed to c0206, AC1 swapped"
ck "C: the branch renames c0006 and swaps a criterion" 1
git reset -q --hard HEAD~1
mkdir -p z-nile/.tracker/issues/c0006x && git mv z-nile/.tracker/issues/done/c0006/check.sh z-nile/.tracker/issues/c0006x/check.sh && git commit -qm "branch: c0006's check.sh moved out of done/"
ck "C2: the branch moves c0006/check.sh out of done/" 1
git reset -q --hard HEAD~1
# 010 F1: main's own later work
mainwork "main: edits two finished files" bash -c 'echo "# a later reviewed comment" >> z-nile/.tracker/issues/done/c0004/check.sh; echo "# a later reviewed comment" >> z-nile/.tracker/rafts/done/R0025/check.sh'
merge_main
ck "main edited c0004 and R0025, merged" 0
mainwork "main: deletes c0007, renames c0008" bash -c 'git rm -rq z-nile/.tracker/issues/done/c0007 && git mv z-nile/.tracker/issues/done/c0008 z-nile/.tracker/issues/done/c0208'
merge_main
ck "main deleted c0007 and renamed c0008, merged" 0
mainwork "main: c0199 finished with an old path" bash -c 'mkdir -p z-nile/.tracker/issues/done/c0199 && printf "#!/usr/bin/env bash\ncheck \"AC1: x\" grep -q Worktrees ../.claude/skills/tracker/SKILL.md\nfinish\n" > z-nile/.tracker/issues/done/c0199/check.sh'
merge_main
ck "c0199 finished on main with an old path, merged" 1
"${RF[@]}" >/dev/null && git commit -qam "c0115: rerun 5c after merging main"
ck "after rerunning 5c as its own commit" 0
# 010: the branch deletes RC3 too; c0040 left unrewritten
sed -i '' '/^check "RC3:/d' z-nile/.tracker/rafts/done/R0025/check.sh && git commit -qam "branch: RC3 deleted too"
ck "the branch deletes R0025's RC3 too" 1
git reset -q --hard HEAD~1
git show "$BASE":z-nile/.tracker/issues/done/c0040/check.sh > z-nile/.tracker/issues/done/c0040/check.sh && git commit -qam "branch: c0040 unrewritten"
ck "c0040 left unrewritten" 1
git reset -q --hard HEAD~1
# 011 F1 for AC13: a skill renamed outside the moves commit, then the ref forged to HEAD
moves_only_from_check() { awk '/^moves_only\(\) \{/{p=1} p{print} p&&/^}/{exit}' z-nile/.tracker/issues/c0115/check.sh; }
ac13() { (export ZN_ROOT=$B HERE=$B/z-nile/.tracker/issues/c0115; eval "$(moves_only_from_check)"; moves_only >/dev/null 2>&1; echo "--- AC13 $1: exit=$? (expect $2)"); }
ac13 "honest" 0
git mv z-nile/skills/zz-stats/SKILL.md z-nile/skills/zz-stats/SKILL2.md && git commit -qm "branch: a skill file renamed outside the moves commit"
ac13 "a skill renamed outside the moves commit" 1
git update-ref refs/remotes/origin/main HEAD
ac13 "...and refs/remotes/origin/main forged to HEAD" 1
git reset -q --hard HEAD~1 && git fetch -q origin
# 010 F1: landed (main is the branch, squashed), then a later main edit
tree=$(git rev-parse 'HEAD^{tree}')
landed=$(git commit-tree "$tree" -p origin/main -m "c0115 landed (squash)")
git push -q origin "$landed:refs/heads/main" && git fetch -q origin && git checkout -q -B landed origin/main
ck "landed: on origin's main itself" 0
mainwork "main: a later edit to c0009" bash -c 'echo "# later" >> z-nile/.tracker/issues/done/c0009/check.sh'
git checkout -q -B landed origin/main
ck "a later main edit after landing" 0
