# Review 004: c0137 (design mode)
Inputs: prep `prep-finished-claude-scans` at 8709695d (c0137.md, check.sh, acceptance/scans.spec.luau, harvest.md, `git diff 6356ecd9 8709695d` including `zz-test/lessons/fixed-lines-run-their-whole-criterion.md` and the new `zz-review/lessons/recommendations-pick-spec-or-check.md`, design-review-001…003, design-refute-001…003). Scratch clone of 8709695d (origin a scratch bare copy, origin/main 22f17750): `./zn check c0137` → `3/3 criteria passed`; `./zn promote-check c0137` → `2 passed, 0 failed … promote-check OK`; `lune run tests/run -- tests/tooling/repo-fence.spec.luau` → `10 passed, 0 failed`.
Dropped from review-003: F1 (fixed as the refute says: the whole-criterion case and its `criterion`/`CRITERIA` helpers are gone from scans.spec, and check.sh AC3 `whole_criteria` runs the three criteria; nothing of it is promoted).

Checked and holding:
- AC3 extraction is complete. `criterion` on each finished file gives the whole script: c0044 AC9 (5 statements), c0067 AC10 through its last line `[ -z "$bad" ] || { echo "$bad"; exit 1; }` (the 13-phrase grep included), R0025 RC1 (both lines). No line inside the three scripts ends in `'` before the closing one, so the awk stop rule cannot truncate them. The runner gives AC3 the same environment (`cd` to the home, `PATH`) as `./zn check` gives the originals.
- Mutants run against AC3's `whole_criteria` (sourced from check.sh, run from a second clone's `z-nile/`). The baseline is `rc=0`, and each mutant below gives `rc=1` with the criterion's own message:
  - M9 (`^name: ready-raft$` restored in c0067 AC10) → `z-ready: name`.
  - M10 ("push files straight to main" restored in the lesson) → the lesson line.
  - "clipboard" planted in pickman-arch → AC10.
  - "./zn launch" planted in z-run → RC1.
  - `<ID>-<slug>.md` planted in zz-test → AC9.
  - `skills/make-prompt` created → AC10.
  - `pickman/skills` moved away → RC1 `a folder this scan reads is missing`.
  - `add/add` removed from zz-rules → AC9.

  M10 sits on AC10's last statement, so it also kills an extractor that stops early.
- `lib/ac.sh` has no per-criterion selection (only `AC_LIST`), so the awk reader is needed rather than a second reader of something that already exists. It stays in check.sh and is never promoted.
- Repository safety: AC3 runs only the three extracted scripts (`grep`, `[ -f ]`, `[ ! -e ]`), all reads. No name from repo-fence's banned list appears in check.sh or scans.spec.
- The lesson fixes: fixed-lines-run-their-whole-criterion's How to apply now points to a check.sh AC. recommendations-pick-spec-or-check transfers to any review that offers two places for a check. Neither just restates a finding.
- Scope: the fix delta touches no Problem, Solution or captured outcome. G1–G3 stand, and the four lines keep AC1.

### F1 [low] Implementation step 1 still expects `./zn check c0137` (2/2), but check.sh now has three criteria
Where: c0137.md Implementation steps, step 1 (line 113).
Evidence: `grep -n "2/2" c0137.md` hits line 113: "Confirm they are on the branch's base: `./zn check c0137` (2/2)". The clone prints `---- 3/3 criteria passed`. (E1's "2/2" at line 66 is a dated record of the prototype run, so it is fine.)
Critique: the executor is told to expect a count the check no longer prints. That costs a question or a moment of doubt, and this is the step that confirms the prep's edits are on the base. Lesson z-design/restated-rules-move-together: AC3's addition did not reach this restatement.
Consequences: none.
Recommendation: change step 1 to "(3/3)".

### F2 [low] harvest.md does not record where zz-review/recommendations-pick-spec-or-check came from
Where: z-nile/.tracker/issues/c0137/harvest.md.
Evidence: the file lists only the four `design-review-00N F…` lines. The new lesson came from review 003's candidate, which is not a finding. The zz-review skill (Lessons) says the lead records "a subagent's candidate … as `- note <what happened>: <lesson ids>`".
Critique: metrics and later readers can't trace the lesson to its source from the harvest. The lesson's own `from:` line names the source, so nothing is lost, but the rule asks for both.
Consequences: none.
Recommendation: add `- note design review 003's candidate lesson (Recommendation offered spec or check.sh AC): zz-review/recommendations-pick-spec-or-check`.

Verdict: approve
