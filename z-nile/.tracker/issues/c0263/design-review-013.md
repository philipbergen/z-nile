# Review 013: c0263 (design mode)
Inputs: prep `prep-ticket-provenance` at a493fe91 (the answer commit 828f65d3 with origin/main merged in): `c0263.md`, `check.sh`, `acceptance/{provenance,publish,record,remap,remap-shapes}.spec.luau`, `experiments/{proto.patch,mutants.py,folder-move.sh}`, `harvest.md`, `design-review-012.md` with `design-refute-012.md` (008 to 011 and their answers read as history; 003 to 007 belong to the unsplit design). origin/main 211c07d2. Prototype `proto-c0263-raft` at d8692784: `git diff 8ffe928c d8692784 -- z-nile/engine z-nile/README.md z-nile/skills` is byte for byte `experiments/proto.patch` (`cmp`), and its five spec copies equal the sequestered ones. `experiments/split/` was not reviewed (sibling hand-off).
Dropped from review-012: F8 (the refutation stands as a decision; see Notes). F1 to F7 were fixed, and I checked each fix (Notes). F1 and F2 added a mechanism, the finish of a hand merge, and this round's F1 and F2 are holes in it.
Capture: `./zn capture c0263` prints `(no capture commit: first add)`, so it is not a confirmed capture. Judged from history: the Problem is unchanged apart from its dated decision lines, and the `Scope decision (user, 2026-11-08)` covers what moved to c0280 to c0284. No scope finding.
Runs, all through `./zn run --time`, in a scratch clone of d8692784 under the session scratchpad (its `origin` a throwaway bare copy; never the real repository):
- (a) `probe013.spec`, three runs on trackerfix fixtures:
  - P2 to P5: the finish path after a hand merge, the second merge stopping, git refusing to start the second merge, and the documented hand path with a document conflict followed exactly (`git add` of the document, then `git add -A`), while main appended to the same record again;
  - P1: `rebase -r`; P1c: a rebase stopped at `edit` with a hand merge of origin/main inside it;
  - C and S: (xv)'s shape, then following the stop's advice (`commit`, `stash`).
- (b) A plain-git script: a merge during a revert in progress.
- (c) The two mutants that do not apply (F4), rewritten for the final code and run against `provenance.spec`.
- (d) Reads: a script that checks every `mutants.py` entry applies once to d8692784, `grep` of the specs and the promoted specs, and the gate's results db for spec durations.

### F1 [medium] When the sync finishes a hand merge, its stop messages give the advice meant for a merge the engine started. Following "commit or stash them" commits git's wrong pairing (our row in another item, exit 0) or throws the hand merge away
Where:
- Behaviour 5, *Write, never over uncommitted work*: "… stops the merge, naming it: commit or stash it."
- zz-rules, Provenance: "an uncommitted change to a record it would have to rewrite (commit or stash it)".
- Prototype `mergeRef`:
  - main.luau:549-550 and 559-560: one message for both paths, "`<path>` has uncommitted changes the merge would overwrite: commit or stash them first";
  - main.luau:488: the HAND trailer is printed in the finish path too;
  - main.luau:622-626: git refusing to start the second merge returns without the `finished` prefix.
- record.spec (xv) checks the stop, then cleans up with `git checkout -- <path>` and `git merge --abort`. It never does what the message says.

Evidence:
- **Run (a) C**, (xv)'s shape. A hand `git merge --no-commit origin/main` is clean, and git pairs our c0063 row into c0064's new record. The user appends a row to c0064's record, unstaged. Then:
  - `./zn sync` stops: `pickman/.tracker/issues/c0064/provenance.md has uncommitted changes the merge would overwrite: commit or stash them first // origin/main is being merged by hand: …`.
  - Following it, `git commit -a --no-edit` commits the merge as git paired it.
  - The next `./zn sync` gives `synced`, with a clean status.
  - c0064's record now reads `Shared, Ours, Scribble`, and `active/c0063/provenance.md` reads `Shared, M1, M2, M3` without `Ours`.
  - This is the exact misattribution (iii) exists to prevent, now committed on our side, so every later sync takes it as a one-sided change.
- **Run (a) S**, the same shape, following `git stash`: `stash` gives `Saved working directory and index state WIP on raft-d`, and then `MERGE_HEAD false`. The stash dropped the user's merge, and their resolutions now exist only inside a stash entry. The next sync re-merges from scratch.
- **Run (a) P3.** A hand merge with only records left, an unstaged edit to `conf3.txt`, and main changes `conf3.txt`. The sync commits the hand merge (`HEAD … Merge remote-tracking branch 'origin/main' into raft-c`), then git refuses the second merge. The output is only `merging origin/main failed; …: error: Your local changes to the following files would be overwritten by merge: conf3.txt …`. Nothing says the hand merge was committed, although Behaviour 5 says "the message says the hand merge was committed".
- **In the finish path the HAND trailer starts with `git merge origin/main`.** The user is already inside that merge, and git answers it with "You have not concluded your merge".

Critique:
- "Commit or stash" is right only where the engine started the merge, because the stop then aborts it and the tree is the user's own again.
- In the finish path the merge is the user's and stays in progress. There:
  - `commit` concludes it without the settling;
  - `stash` resets it away.
- I rate it medium, not high:
  - it needs three rare things together: a hand merge in progress (which happens only after a stop on another file), git mispairing a record, and a hand edit to that very record, which zz-rules forbids ("never edit a row");
  - the engine itself stops correctly;
  - the fix is texts and a case.
- Still, it is the second round in a row where this path's advice fails when followed (review 012 F1). The fix the author will be tempted to make is to change the wording and nothing else.

Consequences:
- The texts must be keyed on who started the merge. `settleAndCommit` already knows (`ours`).
- The finish path needs its own way through. Save the edit, restore the path with `git checkout -- <path>`, run `./zn sync` (it finishes and unites), then put the edit back. Never commit, never stash.
- The started path keeps "commit or stash".
- In the finish path, the HAND trailer drops its first step.
- The `finished` prefix belongs on every return after the hand merge was committed, git's own refusal included.
- Optional: HAND could say `git merge --no-commit origin/main`. Then a hand merge that happens to be clean (git pairing records wrongly, as in (iii)) never commits git's pairing itself, and the hand path always ends in `./zn sync`. That changes the needle of the "a conflict outside provenance.md" case (`git merge origin/main`).

Recommendation:
- Make the two message pairs (overwrite and remove) depend on `ours`, and update Behaviour 5's *Write* sentence and zz-rules to match ("in a merge you started by hand: save your edit, `git checkout -- <path>`, `./zn sync`, then re-apply it").
- (xv) asserts that the output names `git checkout --` and does not say `stash`. It then follows the advice: the sync exits 0, MERGE_HEAD is gone, c0055's record equals main's, and `active/c0054/provenance.md` reads Shared, M1, M2, M3, Ours.
- A case with P3's shape: the output says the hand merge was committed, and HEAD^2 is the old MERGE_HEAD.
- Mutants: "finish-path stop gives the started path's advice", and "finished prefix dropped" (both return sites).

Lesson: z-design/instructions-runnable-where-they-run ("Run the replacement instruction on the failure it answers").

### F2 [medium] Branches added by the round-5 fixes that no case reaches: the second merge stopping after a finished hand merge, `dirty`'s untracked branch, and a revert in progress (which git itself does not refuse)
Where: `mergeRef` main.luau:527-531 (`dirty`), 611 and 627-629 (the second merge), 612-614 (`REVERT_HEAD`); the Rules rows "a hand merge … the newest origin/main is merged on top" ((viii), (ix), never-aborted), "a sync never overwrites uncommitted work" ((x), (xv)) and "a merge of a branch ref does not contain, a cherry-pick, a revert or a rebase in progress is refused" ((vii), (xiv)); design-refute-012 F5 ("A cherry-pick or a revert: git refuses a merge itself").
Evidence:
- **The second merge stops.** Behaviour 5 says: "When that second merge stops, only it is aborted and the message says the hand merge was committed." (ix) is the only case that merges on top, and its second merge is clean. Run (a) P2 shows the prototype gets it right today:
  - the output is `merging origin/main failed (merge aborted); …: your merge was finished and committed; … CONFLICT (content): Merge conflict in conf2.txt`;
  - after it, `HEAD^2` is the old origin/main, MERGE_HEAD is gone, the status is clean, and the record reads Base, Main, Ours.
  
  But nothing pins it. A mutant that drops `finished ..` survives all five specs. So does one that answers the second stop with `git reset --merge ORIG_HEAD`, which also undoes the finished merge.
- **`dirty`'s untracked branch.** `if not tracked then return fs.isFile(path) end` is reached only for a destination git did not write (the file-location shapes, (AU)/(UA)). No case puts a file there, so `return false` survives. Behaviour 5 names it ("(or is untracked)"), but the Rules row does not.
- **A revert in progress.** Run (b): a revert that conflicted, resolved to HEAD's version. `REVERT_HEAD: yes`, nothing staged, then `git merge --no-commit side` prints `Automatic merge went well; stopped before committing as requested`, and `MERGE_HEAD yes`. So git merges during a revert. The engine's `REVERT_HEAD` check is the only guard, and no case or mutant covers it. Round 5 ran only the cherry-pick, which git does refuse.

Critique: these are guards and messages that a wrong implementation drops while `check.sh` stays green. The revert case is narrow (a revert whose resolution is empty), and its failure is recoverable.
Consequences: none beyond the cases. The P2 case shares a fixture with F1's P3 case.
Recommendation:
- record.spec cases:
  - (xvi), P2's shape: exit non-zero; the output names "finished and committed" and "merge aborted"; HEAD^2 is the hand merge's MERGE_HEAD; MERGE_HEAD is gone; the status is clean; the record reads Base, Main, Ours.
  - (xvii), an untracked `provenance.md` at the place the record must go. Use the (AU) shape of "a record only our side added …", where git leaves our record at the old path and writes nothing at the new one: an untracked file sits at the new place before the sync. The sync stops naming it, the file is unchanged, and MERGE_HEAD is gone.
  - (xviii), run (b)'s revert: refused, `REVERT_HEAD` still there.
- Rules rows with the mutants "finished prefix dropped", "dirty ignores untracked files" and "merge: ignores a revert in progress".
- Correct the refute's claim in the Unknowns record: git refuses the cherry-pick, not the revert.

Lesson: zz-test/guard-needs-its-own-case.

### F3 [low] A rebase in progress that holds a hand merge of origin/main is finished, not refused: the code checks MERGE_HEAD before the rebase, and the design orders it the other way
Where: Behaviour 5 lists *Refuse first* ("a cherry-pick, a revert or a rebase in progress") before *Finish a hand merge*. AC6 states both clauses with no order between them. `mergeRef` main.luau:596-621 tests `MERGE_HEAD` first and the rebase directories only in the `elseif`.
Evidence: run (a) P1c.
- A rebase stops at `edit`. The user runs `git merge --no-commit origin/main`, which conflicts on the record. Main then moves.
- `./zn sync` gives `synced to 747dae6`.
- The state afterwards is `HEAD e78d589 Merge remote-tracking branch 'origin/main' into HEAD | rebase-merge true`.
- The log shows two merges (the finished one and the newest on top) inside the user's rebase.
- (xiv) has no MERGE_HEAD, so it cannot see the order. `rebase -r` (run (a) P1) replays the merged commits instead of stopping on the merge, so I found no way into this state except by hand.

Critique: the harm is small, because the user started that merge. But the outcome contradicts the order Behaviour 5 states, and it is the state review 012 F5 wanted refused ("puts a merge of origin/main into the user's rebased history"). Which rule wins has to be decided, not left to the order of an `if`.
Consequences of refusing first: a hand merge made inside a rebase cannot use `./zn sync`, so its record is united by hand. That is rare, and zz-rules says so in one clause.
Recommendation: check `CHERRY_PICK_HEAD`, `REVERT_HEAD` and the rebase directories before `MERGE_HEAD`, and add a case with P1c's shape (refused; `rebase-merge` and MERGE_HEAD still there; HEAD unmoved). Or, if finishing is wanted, state it, never merge the newest on top while a rebase is in progress, and pin that instead.

### F4 [low] Two mutants recorded as `run` do not apply to the recorded prototype tip
Where: Rules rows "the agent-session hint …" (`hint ignores ZN_DISPATCH`) and "a merge across a compaction …" (`guard ignores a one-sided change`). E15 says "the pure and publish ones were killed on the tip before it (their code is unchanged)".
Evidence (run (d)): `mutants.py`'s old texts, checked against d8692784, give `COUNT 0 hint ignores ZN_DISPATCH` and `COUNT 0 guard ignores a one-sided change`, so `python3 mutants.py` prints `NOAPPLY` for both.
- a8ed742c ("format at the repository width") split `or set("ZN_DISPATCH")` over three lines.
- d8692784 removed the third term that the guard mutant's old text quotes.

So "each killed on an assertion" is not true of the tip the table names, and the code is not unchanged (formatting counts for a text mutant). Run (c), rewritten for the final code:
- the guard as `oursCompacted and theirsCompacted and (oursChanged or theirsChanged)` fails `provenance.spec :: a merge across a compaction …`;
- the hint without its `ZN_DISPATCH` term fails `:: grammar and resolution`.

Both are killed, so nothing is untested. Only the record is wrong.
Recommendation: update both entries to the final text. Rerun the whole `mutants.py` on the tip after any formatting commit, and record `NOAPPLY` as a failure of the record.
Lesson: z-design/rerun-skipped-checks-after-edits; z-design/mutant-ids-match-the-runner.

### F5 [low] Texts that still disagree with the round-5 design
- **Edge cases**, line 142: "one that crosses a compaction with records changed on both sides" is the round-4 rule. Line 144: "a merge of the very `origin/main` is finished" is the round-4 equality.
- **E14's last sentences**: "`mergeRef` therefore refuses a merge it did not start … stops across a compaction when both sides changed records" (both are round-4 readings). **E15**: "Rounds 1 to 6 found …", but five rounds had run when it was written.
- **design-refute-012 F7** says "a comment says the compaction map left on main by (v) and (vi) is the reason cases that change a record are placed before them". record.spec has no such comment (`grep -n -i "map\|placed\|order"`). (xii) depends on that order: it passes only because (v) and (vi) ran first.
- **AC7's README clause** (repeat of review 012 F6, the needle part). AC7 says the README "names `provenance.md` and `./zn record` and points there". The docs case checks only `has("z-nile/README.md", "provenance")`, so a README with neither name passes. Add `provenance.md`, `./zn record` and `zz-rules skill, Provenance` (or the README's own words) to the needle.
- **AC6 and Behaviour 5** say "a refusal says nothing was aborted". The messages only leave out "(merge aborted)". Say "a refusal does not say aborted", or have the refusal say "nothing was aborted".

Lesson: z-design/restated-rules-move-together ("does it search for that sentence and find it gone?").

### F6 [low] The harvest filed review 012 F2 under a lesson that cannot catch it
Where: `harvest.md`: `design-review-012 F2: zz-arch/item-rules-scoped-to-their-call`.
Evidence: that lesson is about exemptions decided for one item's check leaking into a general command. Its check ("Does this exemption change the command's answer for callers the decision didn't name …") asks nothing about a helper writing over uncommitted work. The lesson file did not gain a note either. The candidate review 012 proposed ("A merge helper writes only what changed … compare with the index, and refuse a path with uncommitted changes") is in no lesson, and F1 above is that lesson's next failure.
Recommendation: file it as a note on a lesson whose check asks it, or as a new zz-arch lesson, and widen its check to cover F1: "and in a merge it did not start, is its advice runnable without concluding or discarding that merge?". Also correct the harvest line.

Notes (not findings):
- **Round-5 answers checked.**
  - F1: run (a) P4 and P5 follow the documented path exactly. A document conflict and a record conflict; `git merge origin/main`; resolve the document; `git add` it (P5: `git add -A`, staging the record's conflict markers). Main then appends to the same record again. `./zn sync` exits 0, the record reads Base, M1, M2, Ours, the title keeps the resolution, and the status is clean. An older hand merge holding records the newest origin/main changed is therefore sound: the second merge's base is the old MERGE_HEAD, so main's rows stay a prefix.
  - F2: the decide-then-apply order holds. `hash-object -w` writes objects only, and a stop before any `update-index` leaves the index as it was. The unmerged paths are kept out of `dirty`, and a path the merge added is tracked and clean.
  - F3: `itemPathOf` serves the merge, remap's settling and the document search. audit's `STATES` includes `retired/`, so a retired raft's record is audited (no case, harmless). Publishing stays refused.
  - F4: the pure cases pin both directions, and (xii) and (xiii) the merge. With only one map file (base none, one side some), that side counts as compacted.
  - F5: (xiv). F6: fixed, except the README needle (F5 here). F7: (vi) and the vacuous expects are fixed; the comment is missing (F5 here).
  - F8: refuted as a decision. One correction: `tooling/repo-fence` bans `GIT_INDEX_FILE` except through a reviewed per-file allow entry, which c0139 used for `conflicts.luau`, so the window is the author's choice, not a constraint. The choice is acceptable as stated in Behaviour 5.
- **Counts and size.** The cases are 7, 3, 36, 8 and 5 (`grep -c 'it('`), matching the document. `mutants.py` has 80 unique entries, every one named in the Rules table and every table name in `mutants.py`. Three entries (`appendOnly ignores actor/detail/when`) match twice, and `replace(…, 1)` mutates the first match, which is `appendOnly`'s as named. The patch adds 910 lines and removes 25 (935 changed), and `size: 950` fits.
- **Overrides "none": still plausible.**
  - No promoted spec pins the texts this round changed. `git grep -F` over `*/tests/*` and `tests/*` (c0263 excluded) found nothing for these: `merge \`origin/main\` and retry`, `with plain \`git\``, `and merge it into the branch now`, `merging origin/main failed`, `merge aborted`, `another branch is in progress`, `not concluded`, `MERGE_HEAD`, `rebase-merge`.
  - Every engine `git merge` of origin/main goes through `mergeRef`. The others are `--ff-only` in the main checkout and remap's own `--ff-only` of its built merge, and the dispatcher merges PRs with `gh pr merge --squash`.
  - The owed `z-nile/check.sh --affected` (Implementation step 1) stands. Every recommendation above adds cases or changes c0263's own texts.
- **Cost.** In the prototype's gate run (load 50), record.spec took 421 s for its 36 cases. That is beside c0116/retired (424 s), c0043/rounds (411 s) and c0117/control-cli (616 s) in the same run, so not a new outlier. The cases above add about four fixtures' worth of runtime. zz-test's "Monitor continuously" still applies at execution.
- **Repository safety.** The specs write only `.cache` fixtures and commit as `@example.invalid`. `mutants.py` edits the copy `proto-c0263-mut` and restores it. My probes ran in a scratchpad clone with a throwaway origin. `git status` of the prep worktree, the prototype worktree and the main checkout is empty after the runs.
- **Merge states read or run:**
  - a cherry-pick in progress: git refuses (review 012);
  - a revert in progress: git merges (F2);
  - a rebase without MERGE_HEAD: refused, (xiv); with MERGE_HEAD: finished (F3);
  - unmerged entries without MERGE_HEAD (a conflicted `stash pop`): git refuses to start;
  - staged changes: git refuses a non-fast-forward merge;
  - a killed sync that left the engine's own `--no-commit` merge: the next sync finishes it, settling from the commits (idempotent);
  - bisect (a detached HEAD): as before this layer.

Candidate lessons (for the lead):
- **A helper's advice depends on whose operation is in progress.** "Commit or stash" fits a tree the helper restored, but inside the user's own merge it concludes the merge unsettled or resets it away. The check: for each stop message, in each state that reaches it (we started it and aborted; the user started it and it stays), does following the advice, then the next command, give the right result? (F1)
- **A guard's place in an if-chain is a rule.** When two guards can both match one state (a merge inside a rebase), the order decides the behaviour. The check: does the design say which wins, and does a case hold both conditions at once? (F3)

Verdict: changes
