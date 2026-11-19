# Review 004: c0173 (design mode)
Inputs: prep worktree `prep-c0075-read-deploy-workflow` at 17e0424a plus its uncommitted files: c0173.md, check.sh, experiments/ (wiring.patch, c0075-doc.patch, R0039-doc.patch, wiring-case.luau), design-review-001..003.md, design-refute-001..003.md, harvest.md, and the three applied edits (c0075/acceptance/wiring.spec.luau, c0075.md, R0039/R0039.md); capture 76af1f33 (`./zn capture c0173`); c0174's prep worktree (`prep-c0083-read-deploy-workflow`, uncommitted) for the twin state only; z-design SKILL (Scope is what was captured), checklists/chore.md, zz-review SKILL; `./zn lessons --when design`; `z-nile/tests/acceptance/c0120/check-paths.spec.luau` (the RESTAMPED exemption is check.sh-only); `workstreamPlan` in `z-nile/engine/main.luau`.
Dropped from design-review-003: F1 (verified: the patched c0075.md `### No workflow step` and R0039.md Order now carry the re-prep duty, pinned by AC3/AC4; but see F2 for its second option), F2 (verified: E4 credits AC1/AC2 for the unpatched spec, AC5 "passes on purpose"; the Rules table has the base-holds-patch, empty-diff and mode rows; Test plan reworded), F3 (verified: the Regression guard hunk names the search and all seven specs).

Probes (all wrapped in the bounded helper; the clone was under the scratchpad's `c0173-review4/`, from `mktemp -d`, origin URL set to a dead path, deleted afterwards):
- The applied files are exactly 17e0424a's text plus each patch: `git show 17e0424a:<file> | patch -s -f -F 0 -o out` then `cmp out <file>`: OK for all three. `git hash-object` of wiring.spec: `f4a841ef2b6753547982911295c28f33b8270ac1`, mode 100644 in the index and `-rw-r--r--` on disk.
- origin/main moved (17e0424a..13969cce) but `git diff --stat 17e0424a origin/main -- c0075 R0039 c0083 SETUP.md .github z-nile/lib/ac.sh z-nile/engine` is empty.
- In the prep tree: `./zn check c0173` → AC1-AC4, AC6 PASS; AC5 FAIL listing `M …/c0075/acceptance/wiring.spec.luau` and `M …/c0173/check.sh` (5/6). AC5 is red only because this prep's own check.sh is uncommitted, as the lead said. (The `M wiring.spec` line alone is tolerated; the check.sh line is what fails it.)
- Clone, prep committed as `origin/main`, then one empty commit: `./zn check c0173` **6/6**. The lead's claim is true.
- Same clone, c0174's uncommitted files laid on top and committed as a new `origin/main` (its `suites.spec` is blob `db255a0a…`), empty commit: **6/6**.
- Then on that branch, wiring.spec and R0039.md put back to their 17e0424a text: AC1, AC2, AC4 FAIL, AC3, AC5, AC6 PASS (3/6). The branch undoing the prep's edits is red.
- `lune run z-nile/affected -- <the three files> z-nile/.tracker/issues/c0173/experiments` prints nothing; `grep -rlF wiring.spec` and `grep -rlF -e c0075.md -e R0039.md` over both homes' `tests/acceptance` find nothing. No override is missing.

Scope: capture 76af1f33 has the title "C0075 read deploy workflow" and the one-sentence Problem, which the document keeps unchanged. Only the two `Decided with the user (2026-11-01)` lines were added to it. The title change is legitimate: the first decision line records it, quoting the user, and it follows the captured Problem ("read the local jail wiring"). It does not narrow anything: the Design explains why a `deploy.yml` read would add nothing (c0172's promoted `deploy.spec` already pins it), and the user chose that reading. The second decision line moves where the edit is made, not what it does. The captured outcomes ("the case has to read the local jail wiring", no longer `check.yml`, "before c0075 executes") have a Design (The new case, Delivery route) and Checked criteria: AC1 (the file is the patched one and names no workflow) and AC2 (the case's 13 scenarios). "Before c0075 executes" is met by the prep commit: the edit is on `main` before R0039 can be readied. The Delivery route section matches check.sh: AC3/AC4's `exactdoc` takes the "base already holds the patch" branch, AC5 passes an empty diff, and AC1's blob pin stands in for it. Implementation step 1 says the patches were applied in the prep, and step 2 only runs the check, so no step tells an executor to apply a patch.

### F1 [low] Four passages still describe the state before the route decision
Where: c0173.md Chore checklist "Existing work" (line 81); check.sh comment above AC5 (lines 52-53); c0173.md E4 (line 99); c0173.md Lessons pass (line 102).
Evidence:
- Line 81: "If `R0039` is readied before this chore is done, its executor meets a spec reading a deleted file (what this chore removes): no `depends_on` on c0075 is needed: the prep commit carries the edit". Under the decided route the first clause is false (the prep commit lands the case before R0039 can be readied), and the sentence states both rules.
- check.sh:52-53: "The sequestered files this chore may change (route (b)): c0075's wiring.spec, whatever its content … under route (a) the edit is already on the merge base". The Design names (b) only as "not chosen" and never calls the chosen route "(a)", although AC5's Checked text does ("an empty list passes (route (a))"). The executor and the code reviewer will read this sequestered comment as saying the branch may change wiring.spec.
- E4: "`./zn check c0173` on this tree: 1 of 6 (AC6 passes; AC1 to AC4 fail on 'is not the patched file/document' …)". On today's tree I ran it: 5 of 6, with only AC5 red, on the uncommitted check.sh.
- Line 102: "`finished-overrides-land-before-ready` (the delivery route, put to the user)". It has been decided.
Critique: no check gives a wrong result because of these (AC5 still tolerates an `M` of wiring.spec, but AC1's blob pin makes that tolerance dead). They are the defect the lesson names: a decided choice whose body still states the old alternative.
Consequences: check.sh is uncommitted prep text, so it can still be edited now. Its comment is not a grep pattern for any check (check-paths reads command words only). Changing E4 changes no pin.
Recommendation: (1) line 81: "the prep commit carries the edit, so it is on `main` before R0039 can be readied; no `depends_on` on c0075 is needed." (2) check.sh:52-53: "The sequestered files that may differ: none, since the prep commit holds the edit (the decided route). c0075's wiring.spec is still tolerated as an `M`, because AC1's blob pin decides it. c0174's suites.spec is tolerated only exactly as c0174 delivers it." Also drop "(route (a))" from AC5's Checked text, or name the chosen route "(a)" in the Delivery route heading. (3) E4: record today's 5/6 with only AC5 red (the uncommitted check.sh) and the clone states above (6/6, and 6/6 with c0174's twin). (4) line 102: "(the delivery route, decided by the user)". Rerun `bash -n` and `AC_LIST=1` after the comment edit.
Lesson: z-design/decided-guesses-rewrite-their-body

### F2 [low] The re-prep duty's second option, "makes it a member of R0039", is a dead end unless c0173's pins are rewritten too
Where: the patched c0075.md `### No workflow step` ("If c0173 is not done when that re-prep starts, the re-prep also re-preps c0173 (its patches and pins rewritten in a prep) or makes it a member of R0039."); the patched R0039.md Order ("that re-prep also re-preps c0173 or makes it a member."); c0173.md Maintainability.
Evidence: E5 says every other case of wiring.spec is stale, so the re-prep will rewrite the file. Once it lands, AC1's blob pin (`f4a841ef…`) and AC3/AC4's `exactdoc` ("does not apply") judge the re-prepped text on the merge base. Making c0173 a member of R0039 changes neither, so its `./zn check` is red in R0039's raft for ever (its check.sh is sequestered there). The parenthetical "its patches and pins rewritten" sits only on the first option in c0075.md and is missing from R0039.md. Round 3's recommendation had it on both ("re-preps c0173 (or makes it a member of R0039) with its patches and pins rewritten").
Critique: the failure would be loud (AC1's message, and step 2 says escalate), so this is a stall, not a wrong pass. Still, the duty is the only thing that closes round 3's F1 window, and half of it points at a state that cannot pass.
Consequences: both patches change, so AC3/AC4's expected text changes. They must be regenerated, re-applied with `patch -N` on the 17e0424a text, and the clone states rerun (prep tree 5/6 with only AC5 red; clone 6/6). wiring.spec does not change, so the `f4a841ef…` pin stays.
Recommendation: in both hunks, write the second option as "or makes it a member of R0039 and rewrites c0173's check.sh and patches in that re-prep", or drop the member option and keep "re-preps c0173". Then regenerate the two patches, re-apply them, and rerun the clone states. Rows already cover the change (AC3, AC4).
Lesson: z-design/new-rules-migrate-existing-work

Lessons pass: ran `./zn lessons --when design` and asked the relevant checks.
- decided-guesses-rewrite-their-body: F1.
- new-rules-migrate-existing-work: F2.
- exact-checks-compare-against-the-merge-base: passes (both base states verified; the window is closed by the written duty, apart from F2).
- no-vacuous-pass: passes (an empty AC5 is backed by AC1's blob pin, verified by the revert probe).
- finished-overrides-land-before-ready: passes (the edit is in the prep).
- never-narrow-captured-scope: passes (above).
- restated-rules-move-together: passes (the R0039 Order clause loses its "or" before the last item, a cosmetic slip pinned by AC4 and not worth a patch round on its own).
- spec-design-correspondence: passes (E4 and the Rules rows now match the checks).
- no-check-red-between-steps: passes (only AC5 is red, and only before the prep commit; nothing requires a red-first state).
Harvest: the round-3 lines map to existing lessons, and no new lesson file was added.

Chore checklist:
- No behaviour change: true (text only).
- Overrides: none, and the affected-specs and grep searches are empty.
- Existing work: c0075/R0039 are covered. R0039 has no `grouped:` record and `./zn audit` is clean. Line 81's wording is F1.
- Shared state: none.
- Restated rules: the table plus AC3/AC4.
- Moves: none.
- Guards: none; the c0120 check-paths exemption covers c0075's check.sh only, which is unchanged.

Repository safety: check.sh writes only `mktemp -d` scratch (removed) and runs `patch` with `--dry-run` or `-o` to scratch, so it never writes in the checkout. The prep's edits are tracker text.

Verdict: approve
