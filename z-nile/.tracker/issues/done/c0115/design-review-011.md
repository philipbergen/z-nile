# Review 011: c0115 (design mode)
Inputs: prep-c0115 at 6033af5f (`design-review-010.md`, `design-refute-010.md`, `check.sh` AC13 and AC14, `experiments/rewrite-finished.luau` and `rewrite-finished-sim.sh`); prototype `proto-c0115` at 724ddc95 (its `rewrite-finished.luau` is byte-identical to the prep's), used only through scratch clones, with `origin/main` set to d6874ef2 (the c0120-done base).
Dropped from design-review-010: none. F1–F4 are fixed as far as they went (details below); F1 and F3 have new holes in the same mechanisms.

What holds:
- **The round-10 simulation.** `rewrite-finished-sim.sh` reproduces every case the refute claims. The branch alone, main editing c0004 and R0025, c0199 after 5c reruns, landed, and landed with a later edit to c0007 are green. c0199 before the rerun, the branch also deleting RC3, c0040 left unrewritten, and a missing `origin/main` are red.
- **Main deleting or renaming a finished file.** Main deleted `done/c0007`, renamed `done/c0008` to `done/c0208`, and the result was merged: green, 130 files compared. Both are right.
- **Captured on main, then deleted.** c0299 was captured on main with an old path and merged, then deleted on main and merged: green both times. `rewrite-finished` reads only `done/`; `backlog_clean` covers backlog items.
- **F2.** The widened rule 3 rewrites c0040 to `$R/zz-execute/` and `$R/z-design/`, and AC1 and AC2 both exit 0 on the prototype. The old-path scan is independent of the rules (`oldPaths` runs on HEAD's text). No finished file at HEAD still names `.claude/skills/<old>`.
- **F3.** All six bare operands from the base (c0005:54, c0046:41, c0067:63, c0070:42, c0071:30, R0013:26) are rewritten to `skills ../pickman/skills`. With `Cap: 3 rounds` planted in `zz-review`, c0071 AC2's rewritten scan exits 1. A seventh scan is missed, through a variable (F3 below).
- **F4.** Fixed.

### F1 [high] AC14 (and AC13) trust the local `refs/remotes/origin/main`, so a forged ref lets any edit to a finished `check.sh` through (repeat of design-review-010 F1's mechanism)
Where: `experiments/rewrite-finished.luau:258-275` (`rev-parse origin/main`, `merge-base HEAD origin/main`); `check.sh:53-54` (AC13's `moves_only`, same pattern).
Evidence: in a scratch clone of 724ddc95, I replaced c0004 AC1 with `check "AC1: weakened" true` and committed it.
- With an honest `origin/main` (d6874ef2), `--check` prints `c0004/check.sh: not its base text rewritten` and exits 1.
- After `git update-ref refs/remotes/origin/main HEAD`, it prints `no commits since origin/main: checking only that nothing needs a rewrite` and exits 0.
- With `origin/main` forged to the edit commit and one more commit on the branch, it prints `131 finished check.sh files compared with their base text` and exits 0. The base text already contains the edit.

AC13's `moves_only` has the same hole: `[[ -z $(git rev-list "$base..HEAD") ]] … return 0` makes a forged ref equal to HEAD green whatever the moves commit holds. This is the hole c0120's code review just found in the same three-way pattern.

Critique: round 10 made the comparison three-way, but its base is a ref the author controls with one `git update-ref`. The rule then judges nothing, either through an empty range or through a base that already holds the edit. The tempting fix is to also check `git rev-parse origin/main` against `FETCH_HEAD`, which the author controls just as easily.
Consequences: reading the tip from the remote brings in new states.
- Offline, or the remote unreachable: this must fail closed, with a message that says so.
- A tip T that isn't local (not fetched yet): red, "fetch origin".
- After landing, HEAD is T or an ancestor of T, so the merge-base is HEAD and the range is empty. That stays the empty-range rule.
- The remote URL itself can be swapped before the run. The runner fails only if remotes change during a run, so this stays on review's "Caught only by review" list.
- AC13 and AC14 must use one base, or they can disagree on a branch.

Recommendation: question the mechanism, not just this hole: one trusted-base helper for both AC13 and AC14, the same one c0120 adopts (reuse it if c0120 lands first).
- `T = git ls-remote origin refs/heads/main`.
- Red when T is empty or ls-remote fails, or when `git cat-file -e T^{commit}` fails ("fetch origin").
- `M = git merge-base HEAD T`. Red when there is none. The empty range is `M == HEAD`.
- Never read `refs/remotes/origin/main`.

Spec cases in a scratch clone whose `origin` is a local bare repository:
- forged `refs/remotes/origin/main` = HEAD, with an edited finished file: red;
- forged to the edit commit: red;
- remote main not fetched: red;
- `origin` unreachable: red;
- the honest cases of `rewrite-finished-sim.sh`: unchanged.

Do the same for AC13: a forged ref with a bad moves commit is red.
Lesson: ticket-prep/exact-checks-compare-against-the-merge-base (add: the merge-base must come from the remote, never a local ref).

### F2 [high] A finished `check.sh` the branch deletes, renames or moves out of `done/` is never compared, so AC14 is green
Where: `rewrite-finished.luau:280-330`: the loop walks only HEAD's `done/` folders, and a file not at the base "only has to need no rewrite".
Evidence: in the scratch clone at 724ddc95 with an honest `origin/main`:
- (B) `git rm done/c0004/check.sh` on top of an edit to it: `130 … compared`, exit 0.
- (C) `git mv done/c0006 done/c0206`, AC1 deleted and `check "AC9: any" true` appended: exit 0. c0206 isn't at the base, so it only has to need no rewrite.
- (C2) `done/c0006/check.sh` moved to `issues/c0006x/`: exit 0.

Each of these drops or replaces finished criteria, which is what AC14's "nothing else" forbids.
Critique: the comparison is driven from HEAD's side only, so it can't see a file that is missing at HEAD. The tempting fix is to iterate the base's files instead. That loses HEAD's new files (c0199, c0115 and c0113 after `./zn done`), which the current rule handles correctly.
Consequences: c0115 renames and deletes no finished file today (`git diff -M --name-status d6874ef2 724ddc95 -- '*/done/*'` lists only `M`), so a strict rule costs nothing. Main deleting or renaming a finished file stays green, because after the merge the base no longer has it at that path (case D above). The roots must be read at the base too (from the base's `z-nile/projects.toml`), or a root dropped on the branch would hide its files.
Recommendation: also list every finished `check.sh` at M (`git ls-tree -r --name-only M` over each root's `issues/done` and `rafts/done`). Each must exist at HEAD at the same path, or it is red: `<file>: at the base, gone at HEAD`. Keep the HEAD-side loop as it is.

Spec cases:
- B, C and C2 above: red;
- main deletes c0007 and renames c0008, merged: green;
- c0199 finished on main and merged, after 5c: green.
Lesson: testing/no-vacuous-pass

### F3 [medium] c0084's absence scan `grep -rnF -- "--time 0" "$S"` now passes vacuously: rule 1b misses it because the operand is a variable
Where: `z-nile/.tracker/issues/done/c0084/check.sh:60` (`skills_record_every_phase`, `local S=../.claude/skills` at :45); §8, rules 1b and 3.
Evidence: in the scratch clone (z-nile/), `x --time 0 x` was appended to `skills/zz-rules/SKILL.md`. Then `grep -rnF -- "--time 0" ../.claude/skills` exits 1 and finds nothing, while `grep -R` finds the line. The check's `if grep -rnF … "$S"; then … return 1; fi` therefore passes whatever the skills say. At the base, `.claude/skills` held real folders and the scan worked. Rule 1b matches only a literal `<up>.claude/skills` operand, and rule 3 rewrites only `$S/<old>/`, so `"$S"` is left alone. It is F3 of round 10, a seventh time. The other skills variables (c0035 `S`, c0058 `s`, c0040 `R`) are never used bare; I grepped them.
Critique: no by-hand run sees this, because the criterion stays green. The tempting fix is to change S's value to the real folders, which breaks `$S/z-design/` and the other uses on the same lines, or to change `-r` to `-R`, a flag edit the rewrite decision doesn't cover.
Consequences: a rule 1c that rewrites a bare `"$v"` or `$v` operand (then a quote, a space, `)`, `;` or the line's end), where `v` is a rule-3 variable, to the real folders from the home (`skills ../pickman/skills`). The arithmetic is rule 1b's. It touches only c0084:60 today, and the exact check pins it. The quotes go: `"$S"` becomes `skills ../pickman/skills`, two words.
Recommendation: add rule 1c as above, under G13's standing decision (carry). Add an independent scan to `--check`, like the old-path scan: red for any finished `check.sh` with a `grep -…r` whose operand is `<up>.claude/skills` or a variable assigned it. List c0084 in §8's counts.

Mutant: plant `--time 0` in `zz-rules`; c0084's criterion must turn red after the rewrite and stay green without the plant.
Lesson: testing/no-vacuous-pass

### F4 [low] Three finished scans over `.claude` from `z-nile/` read a folder that doesn't exist (since c0120, not c0115)
Where: `done/c0044/check.sh:56`, `done/c0067/check.sh:56` and `rafts/done/R0025/check.sh:15` (`grep -rn… .claude …`), and `c0067:44` (`[ ! -e .claude/skills/make-prompt ]`).
Evidence: neither d6874ef2 nor 724ddc95 has `z-nile/.claude`. Each scan errors (exit 2), and `|| true` swallows the error, so the scan has been vacuous since c0120's home rewrite.
Critique: this isn't c0115's regression, and it is outside this round's scope. But these are skill scans, and c0115 is the move that puts the skills in `z-nile/skills`.
Consequences: none for c0115's acceptance.
Recommendation: capture it as an issue (`lesson`/defect against c0120's rewrite rules). Don't widen c0115.

Candidate lesson (for the lead): a three-way exact check must take its base from the remote (`ls-remote`) and must compare from both sides, the base's files as well as HEAD's. A local remote-tracking ref, and a file that disappeared, each let it judge nothing. Check: "can the author make the base equal HEAD, or make the file absent?"

Verdict: changes
