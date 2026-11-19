# Review 001: R0078 (final mode)
Inputs: the stack at 028c49196 (`R0078/2/c0174`; layers 783ea2626 c0173 and 7c09655c0 c0174, then dfef95636 and the skeleton 028c49196), `git diff origin/main...HEAD` (12 files, all under the raft's folder and the two members' folders). After `git fetch origin main`, origin/main is 4c0990f01, which is also the merge base: main has not moved since the skeleton. Documents read: R0078.md, R0078/check.sh, c0173.md, c0174.md, both `check.sh` files, both harnesses (`wiring-case.luau`, `folder-case.luau`), `wiring.patch`, `suites.patch`, `./zn capture c0173`, `./zn capture c0174`, review-001.md, refute-001.md, harvest.md.

## What I checked
- **Trace**: `trace.md` is filled, 17 rows. `./zn trace R0078 --check` prints `ok: R0078` with the file uncommitted. Every AC row cites its own `check "ACn:` line. The two Problem rows have no check line of their own, so each cites its ticket's AC1 line and says so in the cell. The four "None." rows (c0173 AC7, AC8; c0174 AC6, AC7) are no claims: each cites the "None." line of its document and, in the test cell, the file's `finish` line with the words "no check ... vacuous". No proof is claimed for them. The code cell is `none` on every row, since the checker accepts only that word when the stack changed no source file. `## Source files` is empty for the same reason.
- **Checks, run by me at the merge base 4c0990f01**: `./zn check c0173` passes 6/6 and `./zn check c0174` 5/5. RC1, run by hand (`git diff --name-only <merge base>` filtered by the raft's pattern), finds no file outside the three folders, with my two files present. I did not run RC0.
- **Do the checks prove the claims**:
  - c0173 AC1 and c0174 AC1 pin the whole spec by blob id, so no other case of either file can differ. Both also reverse-apply the patch and grep for the old names. I read both specs: `wiring.spec` names no workflow, and `suites.spec:575` names `.github/workflows/deploy.yml`, which exists.
  - c0173 AC2 runs the case cut out of the real spec against 13 fixture texts: 3 must pass, 10 must fail, and a failure counts only when it is the case's own assertion. A read of any path but `{root}/SETUP.md` errors without that shape, so it is red.
  - c0174 AC2 reads the pair out of the real spec, requires the changed file to exist, and runs the spec's own folder block against the model. It reruns two model defects (a kept leading slash, folder-above-only). The mutants of the block itself (E2's five) were run in prep and are not rerun by this line. The blob pin of AC1 makes that sufficient: the block cannot differ from the one that was mutation-tested.
  - AC3, AC4 (c0173) and AC3 (c0174) compare each document byte for byte with the merge base and require the merge base to hold the patch with no fuzz. I read the patched c0075.md and R0039.md: the "No workflow step" section is there and no sentence tells the executor to add a step.
  - c0173 AC5 and c0174 AC4 diff the working tree against the merge base. The pathspecs match across folders (`*` crosses `/` in git's default pathspec), and the diff is empty.
- **Problem against the capture**: both Problems are word for word the captures'. c0173's title changed from "read deploy workflow" by the user's recorded decision ("Follow the Problem", 2026-11-01); no outcome of either capture is dropped.
- **Nothing extra in the diff**: two Verification logs, two empty `results.txt`, spend rows, `spend.md`, the layer review with its answer and harvest, the skeleton, and R0078.md's moved paragraph. No sequestered file, no experiment file, no source file.
- **The layer review's answer, as the diff shows it**: review-001 F1 is fixed as recommended. `## Order & dependencies` names only c0173 and c0174, the cross-raft sentences sit in `## Cross-raft waits` with lowercase ids and real file names, and c0173's log line says so. F2 (PR comments) is not visible in a diff and I did not judge it.
- **Proofs the matcher could not cite**: none. Every proof is a `check.sh` line.

### F1 [low] Both Verification logs name origin/main 056bf0446 as the stack's base; the stack sits on 4c0990f01
Where: `z-nile/.tracker/issues/active/c0173/c0173.md:166`, `z-nile/.tracker/issues/active/c0174/c0174.md:154` (added in dfef95636).
Evidence: the entries say "`./zn restack R0078` put the stack on origin/main 056bf0446" and "On the stack restacked to origin/main 056bf0446, `./zn check c0174` passes 5/5". `git merge-base origin/main HEAD` prints 4c0990f01 ("tracker: approve d0297", committed 21:07:38), and layer 1's commit 783ea2626 (21:07:52) has it as its parent. 056bf0446 is 4c0990f01's parent. So the checks either ran on a base one commit older than the one the layers were finished on, or the sha was written before the last restack.
Critique: the log is the record of what was verified, and it names a tree the stack is not on. The result is not in doubt: I ran both checks at 4c0990f01 and they pass, and that one commit touches none of the files the checks read. The tempting fix is to leave it, as the difference is one tracker commit.
Consequences: correcting two log lines changes two issue documents after the skeleton. Both are post-finish paths, as dfef95636 was (it came after `Commit:` 7c09655c0 and the trace check passes), so `Commit:` stays. Run `./zn trace R0078 --check` once more after the commit to confirm. No check reads either log.
Recommendation: in the one revision, change both entries to name 4c0990f01, or add "(then 4c0990f01, one tracker commit later; checks rerun there by final review 001, 6/6 and 5/5)". Commit with the filled trace and this review, then rerun `./zn trace R0078 --check`.
Erred: zz-execute
Upstream: none

### F2 [low] R0078.md's Exit criteria say there is no raft-level RCn, and the raft's check.sh has RC1
Where: `z-nile/.tracker/rafts/active/R0078/R0078.md:36` against `R0078.md:23` and `z-nile/.tracker/rafts/active/R0078/check.sh:16`.
Evidence: line 36 says "No raft-level RCn: each member's check.sh carries the exact-document and no-other-change checks." Line 23 says "RC1 pins that, because no other check says 'no code is written' (review F3)", and `check.sh:16` is `check "RC1: the raft changes nothing but its own folder and its two members' folders (no code is written)"`. The answer to design review 001 F3 added RC1 and the Whole-raft sentence and left the Exit criteria as they were. The line is not in this stack's diff; it came with the rafting.
Critique: a reader of the Exit criteria is told the raft has no check of its own, and RC1 is the only check of the claim the raft's Theme makes. Nothing fails because of it: `done` runs `check.sh`, not the prose. The tempting fix is to skip it because the stack did not write the line.
Consequences: R0078.md is a post-finish path and no check or patch reads it (review-001 F1's consequence, which still holds), so the edit changes no check result. RC1 has no row in the trace, since the trace derives rows from issues only; I ran it by hand and it passes.
Recommendation: in the same revision, change line 36 to say "RC1: the diff against the merge base touches only the raft's folder and its two members' folders" in place of "No raft-level RCn".
Erred: z-raft
Upstream: none

## Judged criteria
- None: c0173 and c0174 both say "### Judged: None." There is nothing to rule on, and the trace rows the tool derives from those lines are marked vacuous.

## Candidate lesson
A note on `zz-review/trace-cells-say-when-vacuous`: when the stack changed no source file, `./zn trace --check` accepts only the bare word `none` in a code cell ("expected \"none\""), so the words that say a row is vacuous go in the design and test cells, never the code cell. Why: this review first wrote `none (no code: nothing is judged; vacuous)` and the check refused all 17 rows. Check: in a stack with an empty `## Source files`, is every code cell exactly `none`, and does each non-claim row say it is vacuous in its design or test cell?

Verdict: approve
