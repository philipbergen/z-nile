#!/usr/bin/env bash
# c0271 prep mutation check. Run only in a scratch clone (a separate repository with no origin), with
# experiments/prototype.patch applied and this issue's lesson, harvest, check.sh and acceptance copied in:
#   ./zn run --time 900 -- bash experiments/mutants.sh <clone>
# Each mutant edits the clone, runs check.sh there, expects the named AC to FAIL on an assertion, then restores.
# The guard decides from what git resolves (design review 001 F2), never from the path's spelling: the clone's git
# directory must differ from the one of the checkout that holds this script, and the clone must have no origin.
set -u
C=$(cd "${1:?clone}" 2>/dev/null && pwd -P) || { echo "refusing: ${1:-} is not a folder"; exit 2; }
mine=$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir) || { echo "refusing: cannot read this checkout's git directory"; exit 2; }
theirs=$(git -C "$C" rev-parse --path-format=absolute --git-common-dir) || { echo "refusing: $C is not a repository"; exit 2; }
[ "$(cd "$mine" && pwd -P)" != "$(cd "$theirs" && pwd -P)" ] || { echo "refusing: $C is this checkout's own repository"; exit 2; }
[ "$(git -C "$C" rev-parse --show-toplevel)" = "$C" ] || { echo "refusing: $C is not the top of its repository"; exit 2; }
if git -C "$C" remote | grep -qx origin; then echo "refusing: $C has an origin (a scratch clone has none)"; exit 2; fi
cd "$C" || exit 2
R=z-nile/skills/zz-rules/SKILL.md
X=z-nile/skills/zz-execute/SKILL.md
L=z-nile/skills/zz-rules/lessons/read-pr-state-before-pushing.md
H=z-nile/.tracker/issues/c0271/harvest.md
CK=z-nile/.tracker/issues/c0271/check.sh
SAVE=$(mktemp -d) || exit 2
trap 'rm -rf "$SAVE"' EXIT
cp "$R" "$SAVE/R"; cp "$X" "$SAVE/X"; cp "$L" "$SAVE/L"; cp "$H" "$SAVE/H"
restore() { cp "$SAVE/R" "$R"; cp "$SAVE/X" "$X"; cp "$SAVE/L" "$L"; cp "$SAVE/H" "$H"; }
out=$(bash "$CK" 2>&1); echo "$out" | grep -q -- "---- 3/3 criteria passed" || { echo "BASE not green:"; echo "$out"; exit 1; }
echo "base: 3/3"
fails=0
edit() { R="$R" X="$X" L="$L" H="$H" python3 -c "import os
R,X,L,H=os.environ['R'],os.environ['X'],os.environ['L'],os.environ['H']
def sub(p,a,b):
    s=open(p).read(); assert a in s, (p,a); open(p,'w').write(s.replace(a,b,1))
def body(p):
    s=open(p).read(); i=s.index('\n---\n')+5; return s, s[i:]
$1"; }
run() { # <name> <AC> <python edit>
  edit "$3" || { echo "$1: edit failed"; fails=$((fails+1)); restore; return; }
  out=$(bash "$CK" 2>&1)
  if echo "$out" | grep -q "^FAIL  $2:"; then
    why=$(echo "$out" | grep -A3 "^FAIL  $2:" | grep -v "bounded:" | sed -n 2p | tr -s ' ' | cut -c1-150)
    echo "$1 killed by $2: $why"
  else
    echo "$1 SURVIVED ($2 did not fail)"; fails=$((fails+1))
  fi
  restore
}
control() { # <name> <python edit>: a correct variant every AC must still pass
  edit "$2" || { echo "$1: edit failed"; fails=$((fails+1)); restore; return; }
  out=$(bash "$CK" 2>&1)
  if echo "$out" | grep -q -- "---- 3/3 criteria passed"; then echo "$1 (control) passes 3/3"; else echo "$1 (control) FAILED"; echo "$out" | grep "^FAIL"; fails=$((fails+1)); fi
  restore
}
B='   - **Read the PR before every push to it.**'
run M2 AC3 "s=open(R).read(); i=s.index('$B'); j=s.index('\n',i); line=s[i:j+1]; s=s[:i]+s[j+1:]
k=s.index('5. The human hasn\'t said to hold.\n')+len('5. The human hasn\'t said to hold.\n'); open(R,'w').write(s[:k]+line+s[k:])"
run M3 AC3 "sub(R,' An \`OPEN\` PR takes the push.','')"
run M4 AC3 "sub(R,'\n$B',' **Read the PR before every push to it.**')"
run M5 AC3 "os.remove(L)"
run M6 AC1 "sub(L,'when: both','when: design')"
run M7 AC1 "sub(L,', and does my report quote the state I read?','?')"
run M8 AC1 "sub(L,'PR #256','a PR')"
run M9 AC2 "open(H,'w').write('')"
run M10 AC1 "sub(L,'A \`CLOSED\` or \`MERGED\` one whose head is in your history or in origin\'s branch takes nothing: report its state and newest comment, and stop.','A \`CLOSED\` one is reopened.')"
run M11 AC1 "sub(L,'when: both','when: build')"
run M12 AC1 "s,b=body(L); open(L,'w').write(s+'x'*(1201-len(b.encode())-1)+'\n')"
control C12 "s,b=body(L); open(L,'w').write(s+'x'*(1200-len(b.encode())-1)+'\n')"
run M13 AC1 "sub(L,'tags: [github, landing,','tags: [github,')"
run M14 AC3 "sub(R,' When each test exits 1 (or origin has no such branch), the PR was an earlier use of the branch\'s name (z-stop\'s start fresh), and the branch gets its first push and a new PR, as a branch with no PR does','  A branch with no PR gets its first push and a new PR')"
run M15 AC3 "sub(R,', or \`git ls-remote --heads origin <branch>\` prints a tip and, after \`git fetch origin <branch>\`, \`git merge-base --is-ancestor <headRefOid> FETCH_HEAD\` exits 0','')"
run M16 AC3 "sub(R,' A PR you merged yourself (Merging, or the raft \`./zn done\` landed) is \`MERGED\` by design: its post-merge report and step 4 go on, and nothing more is pushed to its branch.','')"
run M17 AC3 "sub(R,' Any other answer (another \`gh\` or \`git\` error) is no answer: retry once, then push nothing and stop.','')"
run M18 AC3 "sub(X,' The state read before each push and each comment that reports the PR is the exception','')"
run M19 AC3 "sub(X,'or fails twice, nothing is carried past it','nothing is carried past it')"
run M20 AC1 "sub(L,'earlier use of the name','other PR')"
run M21 AC1 "sub(L,'a PR you merged yourself keeps its post-merge report','')"
run M22 AC1 "sub(L,'A read that fails twice stops the push; ','')"
run M23 AC3 "sub(R,'--jq \'{state, headRefOid, newest: [.comments[-2:][] | {author: .author.login, createdAt, body}]}\'','')"
echo "survivors: $fails"
exit $fails
