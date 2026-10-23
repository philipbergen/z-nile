#!/usr/bin/env bash
# Acceptance checks for c0071. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0071 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0071"

P=.claude/skills/ticket-prep/SKILL.md
X=.claude/skills/execute-raft/SKILL.md
T=.claude/skills/tracker/SKILL.md
phase4() { sed -n '/^## Phase 4/,/^## Phase 5/p' "$X"; }
merging() { sed -n '/^## Merging/,/^## /p' "$T"; }
review() { sed -n '/^## 5\./,/^## 6\./p' "$P"; }

check "AC1: ticket-prep allows 5 design rounds, prefers 3, and continues past 3 only when major" bash -c "
  $(declare -f review); P=$P
  r=\$(review)
  grep -qE '5 rounds' <<<\"\$r\" || { echo 'ticket-prep: no 5-round cap'; exit 1; }
  grep -qiE 'prefer[^.]*3|3[^.]*prefer' <<<\"\$r\" || { echo 'ticket-prep: no preference for 3'; exit 1; }
  grep -qi 'high' <<<\"\$r\" && grep -qi 'minor' <<<\"\$r\" || { echo 'ticket-prep: no major/minor condition'; exit 1; }
  ! grep -qF 'Stop after 3 rounds' \"\$P\" || { echo 'ticket-prep: old cap remains'; exit 1; }"
check "AC2: execute-raft caps code review at 5, prefers 3, blocks on the final round" bash -c "
  $(declare -f phase4); X=$X
  p=\$(phase4)
  grep -qF 'Cap: 5 rounds, prefer 3' <<<\"\$p\" || { echo 'execute-raft: no Cap: 5 rounds, prefer 3'; exit 1; }
  grep -qE 'review-NNN\\.md. contains any' <<<\"\$p\" || { echo 'execute-raft: final-round blocking rule'; exit 1; }
  grep -qi 'final round' <<<\"\$p\" || { echo 'execute-raft: no final round'; exit 1; }
  bad=\$(grep -rnF -e 'review-003' -e 'refute-003' -e 'Cap: 3 rounds' .claude/skills || true)
  [ -z \"\$bad\" ] || { echo \"\$bad\"; exit 1; }"
check "AC3: Merging names the final round's review and keeps significant" bash -c "
  $(declare -f merging); T=$T
  m=\$(merging)
  grep -qi 'final round' <<<\"\$m\" && grep -qF 'significant' <<<\"\$m\" || { echo 'tracker Merging condition 1'; exit 1; }"
check "AC4: both skills define minor concretely" bash -c '
  for f in .claude/skills/ticket-prep/SKILL.md .claude/skills/execute-raft/SKILL.md; do
    for k in wording "Rules and mutants"; do
      grep -i minor "$f" | grep -qiF -- "$k" || { echo "$f: minor is not defined with: $k"; exit 1; }
    done
  done'
check "AC6: ticket-prep step 5.5 sets design: ready from the final round" bash -c "
  $(declare -f review); P=$P
  r=\$(review)
  grep -i 'design: ready' <<<\"\$r\" | grep -qi 'final round' || { echo 'step 5.5: design: ready is not tied to the final round'; exit 1; }
  grep -qF 'status <R-id> prepared' <<<\"\$r\" || { echo 'step 5.5: status <R-id> prepared lost'; exit 1; }"
check "AC5: c0038's skill-doc check still passes" bash -c 'bash z-nile/.tracker/issues/done/c0038/check.sh 2>&1 | grep -F "AC3" | grep -q "^PASS"'

finish
