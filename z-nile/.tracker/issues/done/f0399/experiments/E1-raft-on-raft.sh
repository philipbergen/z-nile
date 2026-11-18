#!/usr/bin/env bash
# E1b: a raft R built on unlanded raft D, with tracker state. Layer 1 starts on a base commit = D's top tip plus R's
# folders as on main. After D lands, rebase the layer onto main: only R's own commit, no backlog copy, clean.
set -euo pipefail
cd "$(dirname "$0")" && rm -rf e1b && mkdir e1b && cd e1b
git init -q -b main . && git config user.email a@example.invalid && git config user.name a
mkdir -p src t/rafts/R0001 t/issues/c0001 t/issues/c0002
echo base >src/base.txt; echo "status: prepared" >t/rafts/R0001/R0001.md; echo d1 >t/issues/c0001/c0001.md; echo d2 >t/issues/c0002/c0002.md
git add . && git commit -qm base
# D is readied (moved to active on main) and built: two finished layers
git mv t/rafts/R0001 t/rafts/active-R0001 && git mv t/issues/c0001 t/issues/active-c0001 && git mv t/issues/c0002 t/issues/active-c0002 && git commit -qm "tracker: ready R0001 d"
git switch -qc R0001/1/c0001 && echo d1 >src/d1.txt && git add . && git commit -qm "c0001: d one"
git switch -qc R0001/2/c0002 && echo d2 >src/d2.txt && git add . && git commit -qm "c0002: d two"
# meanwhile on main: R's issue is designed (its folder did not exist when D was cut), rafted, readied
git switch -q main
mkdir -p t/rafts/R0002 t/issues/f0003 && printf 'status: prepared\n' >t/rafts/R0002/R0002.md && printf 'design\n\n## Verification log\n' >t/issues/f0003/f0003.md && echo check >t/issues/f0003/check.sh
git add . && git commit -qm "tracker: prep f0003"
git mv t/rafts/R0002 t/rafts/active-R0002 && git mv t/issues/f0003 t/issues/active-f0003 && git commit -qm "tracker: ready R0002 r" -m "Lands: approved" -m "On: R0001"
# the base commit: D's top tip plus R's folders as on main
git switch -qc R0002/base R0001/2/c0002
git checkout -q main -- t/rafts/active-R0002 t/issues/active-f0003
git commit -qm "tracker: base R0002 on R0001"
BASE=$(git rev-parse HEAD)
# layer 1: start, work (code that needs D's file, an edit to its own document, a results file), finish = squash on the base
git switch -qc R0002/1/f0003 && git commit -q --allow-empty -m "tracker: start R0002 r"
cat src/d2.txt >src/r1.txt; echo "ran the check" >>t/issues/active-f0003/f0003.md; echo ok >t/issues/active-f0003/results.txt
git add . && git commit -qm wip && git reset -q --soft "$BASE" && git commit -qm "f0003: r one"
test "$(git rev-parse HEAD^)" = "$BASE"
echo "layer diff against its base:"; git diff --stat "$BASE" HEAD | sed 's/^/  /'
# main moves on: other work, a publish into R's own member folder (a new file), and D lands by its bind
git switch -q main && echo other >src/other.txt && mkdir -p t/issues/active-f0003/spend.d && echo row >t/issues/active-f0003/spend.d/a.tsv && git add . && git commit -qm "other work and a spend publish"
git switch -q --detach main && git merge -q --no-ff --no-commit R0001/2/c0002 && git mv t/rafts/active-R0001 t/rafts/done-R0001 && git commit -qm "R0001: bind c0001 c0002" && git branch -f main HEAD
# restack R onto main: upstream is the finish commit's parent (the base commit)
git switch -q R0002/1/f0003
git rebase -q --onto main "$BASE" R0002/1/f0003
echo "commits on the layer after the restack:"; git log --format='  %s' main..HEAD
echo "layer diff against main:"; git diff --stat main HEAD | sed 's/^/  /'
test "$(git log --format=%s main..HEAD)" = "f0003: r one"
test ! -e t/issues/f0003 && test -f t/issues/active-f0003/spend.d/a.tsv && test -f src/d2.txt && grep -q "ran the check" t/issues/active-f0003/f0003.md
echo "E1b PASS"
