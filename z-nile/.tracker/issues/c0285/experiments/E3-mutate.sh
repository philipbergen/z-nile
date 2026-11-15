#!/bin/bash
# E3 (c0285): in the prototype worktree (after E3-apply.sh), applies one mutant at a time, runs ./zn check c0285 and
# restores. Usage: ./zn run --time 900 -- E3-mutate.sh <prototype worktree>
cd "$1" || exit 2
L=z-nile/skills/zz-rules/lessons/squash-keeps-the-capture-commit.md
R=z-nile/skills/zz-rules/SKILL.md
I=z-nile/skills/z-ticket/lessons/land-a-challenged-idea.md
H=z-nile/.tracker/issues/c0285/harvest.md
E=z-nile/engine/lessons.luau
S=$(mktemp -d)
save() { for f in $L $R $I $H $E; do cp $f $S/$(basename $f); done; }
restore() { for f in $L $R $I $H $E; do cp $S/$(basename $f) $f; done; }
py() { python3 - "$@"; }
run() { echo "== $1"; ./zn check c0285 2>&1 | grep -E "^(PASS|FAIL)|^      [^ ]" | grep -v "^      bounded\|lessons: \|harvest: every\|c0285: no reviews\|passed, .* failed" | sed 's/^\(....\)  \(AC[0-9]\):.*/\1 \2/' | grep -v "^PASS" | cut -c1-260 | head -6; restore; }
sub() { py "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert old in s, old
open(p, "w").write(s.replace(old, new))
PY
}
save
sub $L "when: both" "when: design"; run "M1 when: design"
sub $L "and list every id its capture commit listed?" "and list its ids?"; run "M2 check drops every id"
sub $L " And does no later commit of that PR change those documents, or does the capture commit reach \`main\` whole (a merge commit)?" ""; run "M3 check drops the later-edit clause"
sub $L "with no marker." "with no marker, and the padding here says the rule again at length with no new fact in it at all, merely to push the body past its cap."; run "M4 body over cap"
sub $L "capture, merging" "merging"; run "M5 tag capture missing"
sub $L ", #265 and #317" " and #265"; run "M6 drops #317"
sub $L "If one does, a squash shows the later text: land the PR with \`gh pr merge --merge\`. " ""; run "M7 how-to drops the merge commit"
mv $L z-nile/skills/zz-rules/lessons/capture-subject.md; run "M15 wrong path"; rm -f z-nile/skills/zz-rules/lessons/capture-subject.md
py $R <<'PY'; run "M8 paragraph above Merging"
import sys
p = sys.argv[1]; s = open(p).read(); i = s.index("The squash subject keeps a capture."); j = s.index("\n", i); para = s[i:j]
s = s[:i] + s[j + 2:]; k = s.index("## Merging\n"); open(p, "w").write(s[:k] + para + "\n\n" + s[k:])
PY
py $R <<'PY'; run "M9 paragraph before the squash command"
import sys
p = sys.argv[1]; s = open(p).read(); i = s.index("The squash subject keeps a capture."); j = s.index("\n", i); para = s[i:j]
s = s[:i] + s[j + 2:]; k = s.index("## Merging\n") + len("## Merging\n"); open(p, "w").write(s[:k] + para + "\n" + s[k:])
PY
sub $R "tracker: new <every id they list> <title> (#<pr>)" "tracker: new <ids> <title> (#<pr>)"; run "M10 subject without every id"
sub $R "The dispatcher's squash takes GitHub's default subject, so a step it merges (a prep, a rafting) must carry no capture commit: its captures land on \`main\` first (by \`./zn land\`, or a challenged idea's pull request)" "A step the dispatcher merges (a prep, a rafting) carries no capture commit, because the dispatcher's squash takes GitHub's default subject: its captures land by \`./zn land\` first"; run "M11 the reversed dispatcher sentence"
sub $R "Their documents are the item documents each capture commit changed (\`git show --name-only --format= <capture sha>\`, without \`spend.md\`, reviews or other files): the text \`./zn capture\` prints. " ""; run "M16 drops the documents definition"
sub $R "--jq '.commits[] | \"\\(.oid) \\(.messageHeadline)\"'" "--jq '.commits[].messageHeadline'"; run "M17 listing prints headlines only"
sub $R "land the pull request with a merge commit instead: \`gh pr merge <pr> --merge --subject \"<title> (#<pr>)\"\`, which brings every capture commit to \`main\` whole" "split it: cherry-pick the capture commits onto a branch off \`origin/main\`, then merge \`origin/main\` into the first pull request"; run "M18 the split instead of a merge commit"
sub $R " A pull request that carries a capture commit keeps it, by its squash subject or a merge commit (Merging)." ""; run "M19 Landing step 3 pointer dropped"
sub $H "- note PR #258" "- dropped PR #258"; py $H <<'PY'; run "M12 no harvest note"
import sys
p = sys.argv[1]; open(p, "w").write("".join(l for l in open(p) if not l.startswith("- dropped")))
PY
echo '-- not_codifiable (simulated c0181)' >> $E; run "M13 c0181 landed, the lesson carries no state"
echo '-- not_codifiable (simulated c0181)' >> $E; sub $L "check: Does" "not_codifiable: a reason the user gave
check: Does"; run "C1 c0181 landed, a state line (control: today's parser refuses the key)"
py $I <<'PY'; run "M21 z-ticket note missing"
import sys
p = sys.argv[1]; s = open(p).read(); open(p, "w").write(s[: s.index("\n**Note (c0285")])
PY
sub $I ", and titled \`tracker: new <id> <title>\`, the subject a default squash takes" ""; run "M22 z-ticket note without the title"
rm -rf "$S"
