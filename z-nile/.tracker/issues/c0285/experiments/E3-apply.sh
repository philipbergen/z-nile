#!/bin/bash
# E3 (c0285): writes the four changes from experiments/ into a scratch worktree (the prototype), as the executor will.
# Usage: E3-apply.sh <prototype worktree> (run under ./zn run)
set -euo pipefail
cd "$1"; X=z-nile/.tracker/issues/c0285/experiments
cp $X/ref-lesson.md.txt z-nile/skills/zz-rules/lessons/squash-keeps-the-capture-commit.md
python3 - z-nile/skills/zz-rules/SKILL.md $X/ref-merging.md.txt $X/ref-landing.md.txt <<'PY'
import sys
p, merging, landing = sys.argv[1], open(sys.argv[2]).read().strip(), open(sys.argv[3]).read().rstrip("\n")
s = open(p).read()
anchor = "\n\nObserved criteria (human Studio playtests) do not block the merge."
assert s.count(anchor) == 1
s = s.replace(anchor, "\n\n" + merging + anchor)
step = "Any other PR is merged with `gh pr merge --squash`."
assert s.count(step) == 1
s = s.replace(step, step + landing)
open(p, "w").write(s)
PY
cat $X/ref-idea-note.md.txt >> z-nile/skills/z-ticket/lessons/land-a-challenged-idea.md
echo '- note PR #258 squashed its capture commit 2e282833 under another subject, so ./zn capture fell back for c0260, c0261, c0263, c0264 and c0265 (the capture of c0285): zz-rules/squash-keeps-the-capture-commit' >> z-nile/.tracker/issues/c0285/harvest.md
