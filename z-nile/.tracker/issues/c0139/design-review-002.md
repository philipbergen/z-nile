# Review 002: c0139 (design mode)
Inputs: prep `prep-scripts-refuse-conflicts` 33a8bb97 (c0139.md, check.sh, acceptance/{markers,conflicts,scripts,audit}.spec.luau, design-review-001.md, design-refute-001.md, harvest.md); prototype `proto-scripts-refuse-conflicts` 2b5b10ed (`z-nile/engine/conflicts.luau`, `main.luau` and `audit.luau` hunks, both c0115 scripts); `./zn lessons --when design --full`. Probes ran in a scratch clone of 2b5b10ed (scratchpad `dr-chores-3/c0139`).
Dropped from design-review-001: F1, F2, F3, F4, F5, F6

Rulings on refute 001: F1–F5 are fixed as answered. I checked the conflict-OK list, the working-tree read (an unstaged and an untracked conflict refuse), `conflicts.folders` shared by every caller, the audit error and its recovery text, fail-closed on the registry, and the F5 search and its exclusions. F6's split into one spec per criterion is right, but the edit that made it left `check.sh` broken (F1 below).

### F1 [high] check.sh doesn't parse: a fragment of the old AC3 is left after AC4, so `finish` never runs
Where: z-nile/.tracker/issues/c0139/check.sh, lines 22–23 (after AC4)
Evidence: the file ends
```
check "AC4: ./zn audit reports … recovery" \
  lune run tests/run -- "$A/audit.spec.luau"

finished refuse over unmerged paths, before writing" \
  lune run tests/run -- "$A/conflicts.spec.luau"

finish
```
`bash -n check.sh` prints `line 22: unexpected EOF while looking for matching '"'`, rc=2. `AC_LIST=1 bash check.sh` lists AC1–AC4, then fails the same way with rc=2 and never prints "criteria listed (none run)". c0114's promoted `classified.spec` lists every unfinished item's check.sh that way and requires that line (`classified.spec.luau:385-395`). So the prep PR's gate is red on this file, and once it is fixed in execution the change is a sequestration violation. The doc's AC2 says "a whole conflict in a working file under a root or a skills folder … naming each path (and line)". The check.sh label drops "under a root or a skills folder" and "(and line)" (lesson z-design/spec-design-correspondence).
Critique / Consequences: sequestered, so it can only be fixed in the prep. Nothing else follows from the fix.
Recommendation: delete the two fragment lines, make the AC2 label match the doc, then run `bash -n check.sh` and `AC_LIST=1 bash check.sh` (expect "criteria listed (none run)") and c0114's `classified.spec` on the prep before committing.
Lesson: z-design/rerun-skipped-checks-after-edits

### F2 [medium] The guard's git reads fail open: an unreadable index reports "no unmerged paths" and the writing command runs mid-merge
Where: prototype `conflicts.unmerged` and `conflicts.marked` (`sh.run` results' status ignored); Design rule 3 is fail-closed for the registry only
Evidence: scratch clone, a real mid-merge with `pickman/src/zz.txt` unmerged. `conflicts.refusal(".", "probe")` gives "refusing to run while the checkout has unmerged paths … pickman/src/zz.txt". With the index made unreadable (`printf DIRC > .git/index`), `git diff --name-only --diff-filter=U` exits 128 ("index file smaller than expected"), and `refusal` returns **nil**. The path is outside the roots, so `marked` can't catch it either. `git grep` exits 1 for "no match" and ≥2 for an error, and `marked` doesn't tell them apart either.
Critique: lesson zz-arch/guard-no-is-explicit: "none" must be one explicit answer (`git diff` ok with empty output; `git grep` exit 1), and every other outcome refuses. c0152 already treats every failed git read as a no, so the two guards should agree.
Consequences: a refusal on a failed read names the git command and its stderr. None beyond that: a checkout whose index can't be read can't commit anyway.
Recommendation: `unmerged` and `marked` return an error on any status other than ok (or, for grep, exit 1), and `refusal` refuses with "can't tell whether …: <command> failed: <stderr>". Add a Rules row and a `conflicts.spec` case (a corrupted fixture index refuses a writing command) with the mutant "status ignored".
Lesson: zz-arch/guard-no-is-explicit

### F3 [low] `conflictOk` counts raw arguments, so `status --project <p>` and `status <id> --project <p>` are refused mid-merge
Where: prototype `main.luau` `conflictOk` (`#cmdArgs <= 1`); Non-goals ("`status` with no argument or one id" runs)
Evidence: scratch clone mid-merge. `./zn status` lists items, while `./zn status --project z-nile` and `./zn status c0139 --project z-nile` both print "refusing to run while the checkout has unmerged paths".
Recommendation: decide on the positional arguments (`flags(rest)`, as the handler does), not the raw count. Add `{ "status", "--project", "z-nile" }` to the conflict-OK loop in `conflicts.spec`.

### F4 [low] Leftover text and fallbacks the F1/F4 fixes didn't sweep
Where: c0139.md Maintainability; prototype `audit.luau` (`conflicts.folders(root)` … `folders or {}`)
Evidence: Maintainability still says "only a command added to `READ_ONLY` is exempt, and that list already means 'reads only'". After F1, the exempt list is `conflictOk`, and READ_ONLY means "may run git-less" (lesson z-design/restated-rules-move-together). In audit, an unreadable registry gives `marked(root, {})`, which runs `git grep … --` with no pathspec and searches the whole repository: design review 001 F4 asked for this fallback to be specified.
Recommendation: rewrite the Maintainability sentence to name `conflictOk`. In audit, report the unreadable registry, which audit surely already reports, and skip the scan instead of widening it to the repository.

Candidate lessons (for the lead):
- zz-test: after any edit to a sequestered check.sh, `bash -n` it and list it (`AC_LIST=1 bash check.sh` must end "criteria listed (none run)") before committing the prep, because c0139's answer to a review left a fragment that broke the whole file; check: does the edited check.sh still parse and list?

Verdict: changes
