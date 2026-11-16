# Review 002: c0122 (design mode)
Inputs: worktree `prep-fence-accepts-empty-fetch` at 0d4323b4 plus its uncommitted `c0122.md`, `check.sh`, `acceptance/{fetch,refuse,wording}.spec.luau`, `design-review-001.md`, `design-refute-001.md`, `harvest.md`; `./zn capture c0122` (b46fadef, a confirmed capture); c0123's prep worktree (`c0123.md`, `acceptance/wording.spec.luau`, `experiments/prototype.patch`, uncommitted); c0189's prep worktree (capture and acceptance folder; its Design is still the template); `./zn lessons --when design --full`; the chore checklist.
Dropped from design-review-001: F1, F2, F3, F4, F5, F6. Each fix is in the document and the specs, and the runs below agree with them. F3's mechanism comes back as F2 below.
Runs (git 2.54.0, every command time-bounded, mutants in a `mktemp -d` clone of the worktree with the prep files copied in, since deleted):
- In the worktree: `./zn check c0122` gives AC1, AC2 and AC4 PASS and AC3 FAIL, naming every phrase and the allowance lines, as E4 says. `./zn promote-check c0122` is OK.
- In the clone: base `fetch` and `refuse` pass 9 of 9. M12 (moves accepted, creations refused) fails AC1 `brings…`, AC1 `--no-prune` and AC2 prune. M5 (deleting a remote-tracking ref allowed) fails AC2 prune and AC2 branch/remote. Both agree with E2.
- Design items 1 to 3 applied exactly as worded: `wording.spec` passes 4 of 4.
- A `git merge-file` of c0123's `fence.sh` hunk with item 2 merges cleanly (F3).
- `set -u` hook mutant: `fetch`, `refuse` and c0131's two specs all pass (F1).
- Tag fetch and `remote.origin.prune` fetch: both refused (F2).

### F1 [high] AC1 never runs a check.sh flow's real environment: a hook that refuses every real check.sh fetch passes AC1, AC2 and AC4
Where: `acceptance/fetch.spec.luau` and `refuse.spec.luau`, `fenced()` (`env = { PICKMAN_FENCE_SPECS = if specs then "1" else "" }`); Design › The end-to-end specs ("fenced … exactly as a check.sh flow"); Rules row "a check.sh flow's real fetch with nothing new succeeds"
Evidence: a real `check.sh` flow never has `PICKMAN_FENCE_SPECS` set. `git grep -n PICKMAN_FENCE_SPECS -- z-nile/lib zn scripts z-nile/check.sh` shows that only `fence.sh` sets it, and only to `1` (line 111). `ac.sh` leaves it unset. The specs instead set it to the empty string, which a shell tells apart from unset.
- I added `set -u` as the hook's second line, a plausible "fail closed" hygiene edit (zz-arch rule 7).
- In the clone, `fetch.spec` and `refuse.spec` then passed 9 of 9, and c0131's `accept` and `refuse` passed 6 of 6, so AC1, AC2 and AC4 all stay green.
- In a fixture fenced by `pickman_fence` with the marker unset, as `ac.sh` leaves it, a fetch with nothing new failed: `reference-transaction: line 49: PICKMAN_FENCE_SPECS: unbound variable` / `fatal: in 'prepared' phase, update aborted by the reference-transaction hook`, exit 128.
- The same fixture with the marker exported empty: exit 0.

So the wrong hook breaks exactly the captured Outcome ("a check can fetch whether or not anything is new"), and every update allowed outside spec runs with it, while all four checks pass. No spec in the gate catches it either: c0131's two specs and c0058's `fence.spec.luau:573` also pass `""`. The Problem says these end-to-end specs exist so that "a change … in how the fence wires the hook" does not go unseen. Their one difference from a real flow is the very variable the rule turns on.
Critique: the tempting fix is to add `unset PICKMAN_FENCE_SPECS` to every case. Then nothing pins the empty value, which `ac.sh` could start passing tomorrow, and the spec-run case needs the variable exported. Another tempting fix is to just list `set -u` as a mutant without changing the specs. That records a mutant no case kills.
Consequences:
- Lune's `process.exec` env table can't unset a variable, so the three-line script has to do it. That changes the script the Design spells out.
- It changes the allow-list reason item 3 gives and AC3 pins ("sets PICKMAN_FENCE_SPECS for that process only"). The repo-fence scan already allows `PICKMAN_FENCE_` in the two files, so the scan needs no new name.
- The spec-run case must still export `1` explicitly, because the runner's own environment has it.
Recommendation:
- Give the script a mode argument and set the marker there: `case $3 in checks) unset PICKMAN_FENCE_SPECS ;; specs) export PICKMAN_FENCE_SPECS=1 ;; *) exit 92 ;; esac`. `fenced()` passes `checks` or `specs`. Spell the new script out in the Design.
- Every check.sh-flow case in AC1 and AC2 runs with the marker unset, which is the real flow. If the empty value should stay covered, add one AC1 fetch with nothing new in a third mode, `empty`.
- Reword item 3's reason, and the line AC3 pins, to say the process sets or clears the marker (for example "fences a .cache fixture in one bash process and sets or clears PICKMAN_FENCE_SPECS for that process only (c0122)").
- Add a Rules row: "a check.sh flow (marker unset, as ac.sh leaves it) fetches" | fetch :: AC1 | the hook with `set -u` (or `${PICKMAN_FENCE_SPECS?}`) | run. Record in E2 that the mutant fails AC1 on its summary line.
Lesson: zz-test/specs-set-host-markers-explicitly

### F2 [medium] The new Ref guard sentence still promises more than the guard allows: a default `git fetch` that brings a new tag is refused whole, and so is `remote.<name>.prune` (repeats design-review-001 F3's mechanism)
Where: Design item 1 (the new sentence: "so a check can fetch whether or not anything is new, as long as it does not prune (`--prune`, or `fetch.prune` in any configuration, … use `--no-prune`)"), item 2, Usability, AC1/AC2/AC3
Evidence (a throwaway origin and clone, the clone fenced by `pickman_fence` as a check.sh flow, marker unset):
- The origin gained a commit tagged `v1` and one tagged `v2` (annotated). `git fetch -q origin` was refused: `fence: a check tried to change refs in the real repository … refused` / `fatal: in 'prepared' phase, update aborted by the reference-transaction hook`, exit 128, with `origin/main` unmoved.
- `git fetch -q --no-tags origin` exited 0.
- After that, the origin made one more commit. A plain `git fetch origin` was refused again: the tags now point into history the clone has, and git's tag auto-follow writes `refs/tags/v1` and `v2` outside `refs/remotes/`. It stays refused until the tags exist locally.
- In the same fenced clone, `git config remote.origin.prune true`, a deleted upstream branch and `fetch --no-tags origin` were also refused. The sentence names only `fetch.prune`.
- This checkout already has one tag (`git for-each-ref refs/tags`: `refs/tags/archive/fixture-leak-2026-09-30`), so the case is not hypothetical.
- `git fetch -q origin main` (the form `./zn` uses) exited 0 with a new tag upstream.
Critique: the issue's deliverable is the sentence a check author relies on. Round 1 found one unstated exception (prune). Round 2 finds two more in the same promise: tags auto-followed by a default fetch, and the per-remote prune key. Enumerating exceptions to a broad "a check can fetch" promise has now failed twice. The tempting fix is to add "or tags" to the parenthesis. That leaves the next one (`fetch.pruneTags`, a `+refs/…:refs/heads/…` refspec, `remote.<name>.tagOpt`) for round 3.
Consequences:
- Whether the guard should accept a fetch that creates tags is a guard widening. The capture says "any update outside `refs/remotes/` … stays refused", so that is the user's call, not this issue's.
- The text has to name the safe form, and one real-git case per exception class has to pin it, or the promise drifts again.
Recommendation:
- Replace the enumerated exception with the positive rule plus one safe form. For example: "a check's fetch is accepted only when every ref it writes is created or moved under `refs/remotes/`, or it writes none (a fetch with nothing new, c0131). Anything else refuses the whole fetch: a pruned ref (`--prune`, `fetch.prune` or `remote.<name>.prune`) or a tag git follows into `refs/tags/`. So a check fetches with `git fetch --no-prune --no-tags origin`."
- Mirror that in item 2's line and in AC3's pinned phrases.
- `refuse.spec` (AC2, check.sh flow): the origin tags a new commit. A default `git fetch origin` is refused with the guard's message, `refs/remotes/origin/main` has not moved, and no `refs/tags/` ref was created.
- `fetch.spec` (AC1): the `--no-prune` case becomes `--no-prune --no-tags`, with a tag and a deleted branch upstream. It succeeds, follows `main` and creates no tag.
- Add the rows (a "tags allowed" hook mutant kills the new refuse case; record it as run).
- If accepting tags or prunes is wanted, escalate to the user as a new capture. Don't decide it here.
Lesson: candidate for the lead (design-review-001 F3 was harvested as "one-off" and has now recurred): z-design/promises-name-their-exceptions. A rule text that promises a capability ("a check can fetch") states it as the guard's positive condition plus the one safe invocation, and has a real-git case for each class the guard refuses. Check: "which ordinary configurations or defaults of the tool (prune, tag following, per-remote keys) make the promised command do something the guard refuses?"

### F3 [low] Existing work says c0123 and this issue conflict on `fence.sh`'s header, but they edit different lines and merge cleanly
Where: Design › Checklist › Existing work, the c0123 bullet ("whichever of the two lands second gets a text conflict on line 101 and on `fence.sh`'s header"), Implementation step 5 ("resolve line 101 … and `fence.sh`'s header by hand")
Evidence: c0123's `experiments/prototype.patch` hunk `@@ -12,7 +12,7 @@` changes line 15 (`# The ref guard's hooks are the git-hooks/ folder … , pinned by content (c0123).`). This issue changes line 10 (`#   - refuses ref updates …`). `git merge-file -p ours base theirs` with the two edits gives exit 0 (no conflict) and keeps both lines. c0123's own document says "one phrase to the header", which is true, but the phrase is on another line. The line-101 conflict in the zz-test skill is real and correctly described.
Recommendation: say that only line 101 of the zz-test skill conflicts, and that `fence.sh`'s two header edits sit on different lines and merge without a conflict. Implementation step 5 then checks that both header phrases are present (both wording specs do) instead of resolving anything by hand.

### F4 [low] AC3's allowance case pins repo-fence.spec's layout forever, although after promotion the scan itself is the check
Where: `acceptance/wording.spec.luau`, "AC3: the gate scan's allowance for the two end-to-end specs is in place"; Design item 3
Evidence: the case requires the four literal lines of item 3's block in `z-nile/tests/tooling/repo-fence.spec.luau`. It exists because the scan visits the two specs only once promoted (design-review-001 F2). Once `done` promotes them, `repo-fence.spec`'s own scan fails if the allowance is missing, so the wording case adds nothing. But it remains a promoted spec pinning another spec's text. Any later reshaping of the allow-list (for example folding the per-item loops into one table, or dropping the 'c0122' literal) turns c0122's promoted wording spec red and needs an Override chore (lesson zz-test/promoted-specs-pin-rules-not-sets).
Recommendation: keep the case, since it is the only pre-promotion check, but make its pin the rule rather than the layout. Two ways:
- Have the case evaluate the allowance as the scan does. Load the `ALLOWED` table's entries for `z-nile/tests/acceptance/<renamed id>/{fetch,refuse}.spec.luau` and require `PICKMAN_FENCE_` with a non-empty reason, not exact source lines. That needs the table exported, a change to `repo-fence.spec`.
- Or keep the text pin but say in the Design that a later reshaping of the allow-list overrides this case, naming the case.
Either way, record which you chose in the Rules row.

Verdict: changes
