#!/usr/bin/env bash
# c0271 prep mutation check. Run only in a scratch clone under /tmp (never the real repository), with
# experiments/prototype.patch applied and this issue's lesson, harvest, check.sh and acceptance copied in:
#   ./zn run --time 600 -- bash experiments/mutants.sh <clone>
# Each mutant edits the clone, runs check.sh there, expects the named AC to FAIL on an assertion, then restores.
set -u
C=${1:?clone}
case "$C" in /tmp/*|/private/tmp/*|/var/folders/*) ;; *) echo "refusing: $C is not a scratch clone under /tmp"; exit 2;; esac
cd "$C" || exit 2
R=z-nile/skills/zz-rules/SKILL.md
L=z-nile/skills/zz-rules/lessons/read-pr-state-before-pushing.md
H=z-nile/.tracker/issues/c0271/harvest.md
CK=z-nile/.tracker/issues/c0271/check.sh
save() { cp "$R" /tmp/c0271-R; cp "$L" /tmp/c0271-L; cp "$H" /tmp/c0271-H; }
restore() { cp /tmp/c0271-R "$R"; cp /tmp/c0271-L "$L"; cp /tmp/c0271-H "$H"; }
save
out=$(bash "$CK" 2>&1); echo "$out" | grep -q -- "---- 3/3 criteria passed" || { echo "BASE not green:"; echo "$out"; exit 1; }
echo "base: 3/3"
fails=0
run() { # <name> <AC> <python edit>
  python3 -c "$3" || { echo "$1: edit failed"; fails=$((fails+1)); restore; return; }
  out=$(bash "$CK" 2>&1)
  if echo "$out" | grep -q "^FAIL  $2:"; then
    why=$(echo "$out" | grep -A3 "^FAIL  $2:" | sed -n 2,3p | tr -s ' ' | cut -c1-160 | tr '\n' ' ')
    echo "$1 killed by $2: $why"
  else
    echo "$1 SURVIVED ($2 did not fail)"; fails=$((fails+1))
  fi
  restore
}
B='   - **Read the PR before every push to it.**'
run M2 AC3 "
p='$R'; s=open(p).read(); i=s.index('$B'); j=s.index('\n',i); line=s[i:j+1]; s=s[:i]+s[j+1:]
k=s.index('5. The human hasn\'t said to hold.\n')+len('5. The human hasn\'t said to hold.\n'); s=s[:k]+line+s[k:]; open(p,'w').write(s)"
run M3 AC3 "
p='$R'; s=open(p).read(); s=s.replace(' Only an \`OPEN\` PR takes the push.','',1); open(p,'w').write(s)"
run M4 AC3 "
p='$R'; s=open(p).read(); s=s.replace('\n$B',' **Read the PR before every push to it.**',1); open(p,'w').write(s)"
run M5 AC3 "
import os; os.remove('$L')"
run M6 AC1 "
p='$L'; s=open(p).read(); s=s.replace('when: both','when: design',1); open(p,'w').write(s)"
run M7 AC1 "
p='$L'; s=open(p).read(); s=s.replace(', and does my report quote the state I read?','?',1); open(p,'w').write(s)"
run M8 AC1 "
p='$L'; s=open(p).read(); s=s.replace('PR #256','a PR',1); open(p,'w').write(s)"
run M9 AC2 "
open('$H','w').write('')"
run M10 AC1 "
p='$L'; s=open(p).read(); s=s.replace('A \`CLOSED\` or \`MERGED\` one takes nothing: report its state and newest comment, and stop.','A \`CLOSED\` one is reopened.',1); open(p,'w').write(s)"
run M11 AC1 "
p='$L'; s=open(p).read(); s=s.replace('when: both','when: build',1); open(p,'w').write(s)"
echo "survivors: $fails"
exit $fails
