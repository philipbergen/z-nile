# Review 009: c0120 (code mode; the coordinator's round 006 of #107)
Inputs: `origin/impl2-c0120` at 7a01bd47 (PR #107). The fix delta is `git log --first-parent c601e77e..7a01bd47`: 39bee1d, then the merges 1925b4e, 42b1bef and 7a01bd4. The prep commits merged in are `origin/prep-c0120` 676dfa8e..6f6adf61: 554b6c8, 16388e7 and 6f6adf6. `git diff 6f6adf61 7a01bd47 -- z-nile/.tracker/issues/c0120` is empty. I read review-008, refute-008, c0120.md (Guess 18, Rules rows V26 to V28, §14b, steps 12 and 13, JC1), `./zn lessons --when build --full` and the review lessons first. Every run was in scratch clones under `code-review-c0120b-006/`, each with a local bare repository as its `origin`. Nothing was fetched into, run in or written to the real repository or its `.worktree/*`. The real remote was only read, with `git ls-remote` and one bare clone.
Dropped from review-008: F2, F3 and F4, each fixed as refute-008 says (checks below). F1 is fixed for the forged local ref and the unfetched tip. The swapped origin is a limit under the user's "detect, not prevent", but it isn't written down (F4 here). F5 is fixed for deletions only (F3 here).
The user's decisions applied: "Reviewer-pinned commit" (AC18) and "Reviewed by commit group" (earlier groups untouched; the new commits are judged as one group).

## What was run
- **Gates**, each in its own clone at 7a01bd47:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1162/173, z-nile 846/123.
  - `pickman/check.sh --full`: GATE PASSED. 1162/173.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 846/123.
- **c0120's `check.sh`** (`./zn sync --fetch`, then `./zn check c0120`): 15/18. Each red is an allowed one, red for its stated reason:
  - AC11: only c0114's `tracker/next (from z-nile)` and `z-nile/next (from z-nile)`;
  - AC16: only `busy: cannot read origin/main`;
  - AC18: `no approved review … records a "Prep reference: <sha>"`.
- **Promotion dry run.** `git mv` of c0120's `acceptance/` to `z-nile/tests/acceptance/c0120`, then `z-nile/check.sh --full`: static stages clean; pickman 1162/173; z-nile 950/137 with 1 failure, check-paths' live case, which is AC11's expected red (c0114's two lines).
- **AC18's published-tip reader** (`rewrites.mainBase`). Clone `atk`, with an approving stub `review-009.md` that pins 6f6adf61 and its own bare origin:
  - stub alone: green, 222;
  - **forged local ref.** Commit C on the merge-base adds `# forged` to c0122's `check.sh`. C is merged, the line is placed, and `refs/remotes/origin/main` is set to C: **red**, `pickman/.tracker/issues/c0122/check.sh: changed`;
  - **unfetched tip.** Another clone pushes a commit to the bare origin: **refused**, `origin's main 2e95a700… is not here: run ./zn sync --fetch`. Green once fetched;
  - **published tip moved onto the branch** (the branch pushed as main and fetched): **refused**, `already holds the move`. With the tip moved back to the tree before the move: green. That is a rewind to a commit the branch holds, so it judges nothing weaker;
  - **origin swapped** to a repository I control whose `main` is C, three ways (`remote set-url`, a local `url.<evil>.insteadOf`, and `GIT_CONFIG_COUNT`/`KEY`/`VALUE` in the environment): **green** each time, `main 393b65d2…`. This is a limit (F4);
  - **a look-alike ref** `refs/heads/a/refs/heads/main` pushed to origin: **refused**, `cannot read origin's main`. One that sorts after `main` (`zz/refs/heads/main`): green, the right tip (F5).
- **F2** (`spec-not-promoted`):
  - c0002's specs (promoted before the move) moved back into `done/c0002/acceptance`: AC18 **red**, 3 × `not promoted`; `./zn audit` reports `spec-not-promoted`;
  - c0072's promoted specs moved to the wrong home (`z-nile/tests/acceptance/c0072` to `pickman/tests/acceptance/c0072`): AC18 green, because any home's `tests/acceptance` counts as promoted. `./zn audit` catches it (`misplaced-spec`, AC15 and the gate), so this is no finding.
- **F3**, on the merged tree below:
  - main compacts d0124 to d0138, with a line in `tracker/compaction.txt`;
  - the branch follows, with the line placed in `z-nile/compaction.txt` (the real form; finished.spec's case leaves the line out): green;
  - without the line: green;
  - the renumbered `check.sh` edited: **red** `changed`;
  - the old d0124 copy kept: **red** `kept, though the main it merged removed it`.
- **F4**: see F2 here.
- **F5**: main renumbers c0134 (captured after the move's base) to c0138, and the branch keeps a copy at c0134: **green** (F3 here).
- **Whole-main merge simulation** (clone `msim`, from 7a01bd47 with the stub review):
  - **The merge.** `git merge -s ours --no-commit` of today's real `origin/main` 34dc336e (read with `git ls-remote` from GitHub; 87 commits past the merge-base f50a610a). Main's changes were placed with review-008's `resolve.py` (new tooling items to z-nile: c0127, c0131, c0132, c0134 to c0137, R0047). Five non-sequestered conflicts were resolved by hand: the testing skill, two lessons as unions, and two lessons kept as the branch had them.
  - **Main's ready of R0043 followed.** The branch's leftover files in `z-nile/.tracker/{issues/c0114,rafts/R0043}` were moved to `active/`, or dropped where main's copy is identical.
  - What this brought in:
    - R0043 readied (active);
    - c0133 withdrawn;
    - c0127 and c0131 finished (R0047), their specs promoted on main;
    - c0134 to c0137 captured;
    - d0124, R0044 and R0045 prepped.
  - **Step 12.** `rewrite-finished.luau` changed 1 of 140 files (c0127's `check.sh`).
  - **AC18: green, 251.** override-markers: **all 970 hunks marked**.
  - **c0114's `done`**, simulated:
    - c0114 and R0043 to `done/`, and `acceptance/` to `z-nile/tests/acceptance/c0114`;
    - `c0114-overrides.patch` (`git apply --index`, clean);
    - `rewrite-finished` (2 files).

    **AC18: green, 251. override-markers: all 1088 marked.**
  - **Gates on the merged tree** (three clones): **red**. `pickman/check.sh --full`: 1402 passed, 2 failed. `z-nile/scripts/check.sh --full`: 852 passed, 21 failed. `z-nile/check.sh --full` stops on pickman's 2. Every failure traces to main's own content, specs and code written for the old layout:
    - `tests/acceptance/c0127/reuse.spec` (12) and `tests/acceptance/c0131/{accept,refuse}.spec` (4), promoted on main by R0047. They name `{root}/scripts/lib/git-hooks/reference-transaction` and `{root}/scripts/lib/{ac,fence}.sh`, and write `{root}/.cache`, which the jail denies from `z-nile/` (`Operation not permitted`);
    - `tests/tooling/lock-start-ids.spec` (3), a new tooling spec on main, the same way;
    - repo-fence's two cases, in z-nile and in pickman's scan copy `tests/meta/fence.spec`: the allow-list keys main added are pre-move paths, and those specs name `PICKMAN_FENCE_`;
    - main's c0131 change to `scripts/lib/git-hooks/reference-transaction` belongs to `z-nile/lib/git-hooks/` (c0114 moved the hook there). The resolver put it under `pickman/scripts/lib/`. I ported it with `git merge-file` (clean).

    The tooling spec and repo-fence's keys are hand-written core: the executor can fix them. The promoted specs are sequestered, and fixing them turns AC18 red (F1).
- **Fence spot-check (item 8).** Clone g4, macOS as shipped. A fingerprint (refs, local config, HEAD, `ls-files -s`, worktrees, hooks, stash) was identical before and after.
  - Two probe items, a pickman one (f9998) and a z-nile one (c9998). Inside `check`, each runs `rev-parse`, `update-ref`, `add -f -N` and `commit` in `.cache` and `.cache/atk` of the root, `pickman/` and `z-nile/`, plus an `update-ref` from its home. f9998 also runs `git ls-remote origin`.
  - Each probe runs from the root, `pickman/` and `z-nile/`, under four environments: none, `GIT_DIR=.git`, an absolute `GIT_DIR`, and a ceiling at the root.
  - **24 runs, 0 open, no `pwn` refs.**
  - `ls-remote` works inside a `check`. Under an inherited root ceiling it fails, so AC18 refuses there, which is fail-closed.
  - An earlier run showed that a `check` may move `refs/remotes/origin/main`. That is the testing skill's documented fetch allowance, harmless now that AC18 reads `ls-remote`. I restored the ref, and the fingerprint matched again.
- **Sequestration (item 2).** The new group changes no sequestered file outside c0120's own folder: `finished.luau`, `finished.spec.luau`, `override-markers.luau`, `rewrites.luau`, all through the prep (Guess 18).

### F1 [high] After the mandatory merge of today's origin/main, AC18 and the z-nile gate can't both be green: c0127's and c0131's specs, promoted on main, need the move's overrides to run from `z-nile/`, and AC18 rejects any edit to a spec main promoted
Where: `finished.luau`'s three-way verdict (a file main changed between B and M has M's text as its reference, so the branch's edit is `changed`). c0120.md §14b and step 12 (they move a "newly promoted folder" by §1's rule and say nothing about overriding it). JC1's group 3 and the user's override decision cover only specs promoted before the move.
Evidence: in `msim`, after the whole-main merge and c0114's `done`:
- `z-nile/tests/acceptance/c0131/accept.spec.luau` fails from `z-nile/`. It reads `{root}/scripts/lib/git-hooks/reference-transaction` and writes `{root}/.cache/c0131-accept`. c0127's `reuse.spec` and c0131's `refuse.spec` fail the same way: 16 failures in z-nile's gate.
- I replaced those two lines with `{root}/z-nile/lib/git-hooks/…` and `{root}/z-nile/.cache/…`, under a `-- c0120 override:` marker. The spec then passes 3/3 and override-markers marks all 1089 hunks.
- AC18 is then **red**: `z-nile/tests/acceptance/c0131/accept.spec.luau: changed`.

So step 12's merge leaves the executor two choices: a red gate, or a red AC18. Review-008's "a marked weakening of c0129's promoted spec: red" was right for a weakening. It didn't separate a weakening from an override the move needs: c0129 is a game spec, which needs none. c0127 and c0131 are the first tooling items finished on main since the move's base. They were already on the main refute-008 merged (e3435fb7 holds all three specs), but that simulation ran only AC18 and override-markers, not the gates.
Critique: the tempting fix is to let AC18 hand main-promoted specs to override-markers, as 676dfa8 did for specs promoted before the move. Override-markers proves only that each hunk is marked, so a marked `error()` → `return` would pass. Review-008 called that red, rightly, and this would undo it. Another tempting fix is to override them anyway and call AC18's red allowed, which leaves AC18 permanently red at `done`. Both widen or drop sequestration, which is the user's decision, not the author's.
Consequences: every later main merge can bring more of these, since each tooling raft that lands promotes old-layout specs. The fix has to be repeatable per merge, reviewable, and kept out of the author's hands, like c0114's `c0114-overrides.patch`. Main's tooling code changes to files c0114 moved (c0131's hook edit, `scripts/lib/git-hooks` → `z-nile/lib/git-hooks`) also need a placement rule. §1's rule as `resolve.py` applies it sent that edit to `pickman/`, silently, and only c0131's own specs noticed.
Recommendation: escalate to the user. The options, with what each costs:
- (a) **A reviewed overrides patch per main-promoted spec**, in c0120's folder, changed only in prep. AC18 accepts exactly M's text with that patch applied, as it does for c0114. It costs a prep round per merge that brings tooling promotions, and keeps the reference out of the author's hands. This is my recommendation.
- (b) **Main-side chores** that make c0127's and c0131's specs layout-neutral (resolve the hook and `.cache` through the registry or the runner's `ZN_ROOT`/home) before c0120 lands. The branch then needs no override, but it serializes c0120 behind main work, and every new tooling raft must do the same until c0120 lands.
- (c) **override-markers alone** for these specs: the cheapest, and it reopens review-008's marked-weakening hole.

Whichever is chosen:
- §14b and step 12 gain a line: a spec main promoted during the window that needs the move's paths is overridden by the chosen mechanism, and main's edits to files c0114 or c0120 moved go to their new place (c0114's map, then c0120's), never by §1's default rule.
- finished.spec cases:
  - main promotes a tooling spec that names `{root}/scripts/lib/…`, and the branch overrides it by the mechanism → green;
  - the same with one extra unmarked or unpatched line → red.
- The coordinator's whole-main simulation runs the three gates, not only AC18 and override-markers.

Lesson: review/sequestration-reference-not-a-ref (its "prove it with a real merge of all of origin/main", here the gates as well).

### F2 [medium] F4's fix lets a commit the author makes choose the world the finished rewrite is judged in: a transient file makes AC18 accept an un-rewritten finished `check.sh` whose scans then find nothing
Where: `finished.luau` `worldAt`: `git log -1 --format=%H HEAD -- <path>`, then `rewrites.world(TOP, pre, rev)` at that commit, unless it is an ancestor of group 4. `rewrites.rewrite` keeps a literal whenever `world.now(<home>/<path>)` holds.
Evidence: clone `atk`, from the stub commit:
- **Commit C** adds a stray `z-nile/.claude/skills/execute-raft/SKILL.md`. It also sets c0067's finished `check.sh` to `rewrites.rewrite(pre text, "z-nile", world(C))`, which is the shipped text with two literals un-rewritten: `../.claude/skills/execute-raft/SKILL.md` becomes `.claude/…`, and `../.claude/skills` becomes `.claude/skills`.
- **Commit D** removes the stray file. The net diff is that `check.sh` alone, 2 lines.
- AC18: **green, 222**. override-markers: green.
- At HEAD, c0067's AC10 line `! grep -qF "moves the items to \`active/\`" .claude/skills/execute-raft/SKILL.md` runs from `z-nile/`, where there is no `.claude`, so grep fails and `!` passes: **vacuous**. The `../.claude/skills` banned-phrase scan likewise finds nothing.
- Before 16388e7 the world was HEAD's, and the same un-rewrite needed the stray file at HEAD, where JC1's content diff shows it.

What still catches it: AC11's finished half (`finished.spec` "every finished check.sh … resolves from its home") fails, naming both literals. AC11 is an allowed red today, though (c0114's two lines), so its criterion line reads `FAIL` either way until c0114 lands.
Critique: this is the lesson's question again: the world is part of the reference, and `log -1` hands it to whoever makes the last commit touching a file. The tempting fix is "AC11 covers it". That leaves AC18's verdict author-chosen, and AC11 is red, so it hides a second failure. Another tempting fix is to read the world from the merge that made a text. Merges are the author's commits too.
Consequences: F4's own goal (a file committed later doesn't change what is expected) must still hold for group 2 texts. A later text (a step-12 rewrite after a merge) was made against the tree at that time, which is again the author's.
Recommendation:
- AC18 judges a finished `check.sh` against at most two worlds, neither chosen per file. Group 4's tree for a text from group 2 or 3: fixed by the user's groups, and pinned by checking that commit's subject or sha (refuse when the third first-parent commit after the move isn't `c0120: run each project from its home …`). And HEAD's tree. It accepts the text when it equals the rewrite under either.
- Cases:
  - the transient plant above (C plants the file and the matching text, D removes the file) → red;
  - an unrelated tracked file added at HEAD at a rewritten path's home-relative place → still green (F4's case);
  - a mutant `worldAt` that returns the `log -1` commit → killed by the first case.

Lesson: review/sequestration-reference-not-a-ref; testing/no-vacuous-pass (the vacuous scan).

### F3 [low] F5's fix sees main's deletions but not its renames: an item main captured after the move's base and then renumbered stays unknown, so a copy the branch keeps at the old id is never judged (repeat of review-008 F5)
Where: `finished.luau` `removedOnMain`: `git log --format= --name-only --diff-filter=D B..M`. git's log detects renames by default, so a renumbered folder shows as `R`, not `D`.
Evidence: in `msim` after c0114's `done`:
- main commits `git mv tracker/issues/c0134 tracker/issues/c0138` (c0134 was captured on main after B).
- The branch merges it and follows to `z-nile/.tracker/issues/c0138`, but keeps a copy at `z-nile/.tracker/issues/c0134`. AC18: **green, 251**.
- `git log -M` on that commit shows `R100 tracker/issues/c0134/check.sh tracker/issues/c0138/check.sh`.

Review-008 F5's Recommendation asked for "deletions and renames". finished.spec's F5 case removes f0093 with `rm`, and its renumber case uses f0071, which is in `pre`, so neither reaches this.
Recommendation: add `--no-renames` to that `git log` (or `--diff-filter=DR` with the old side of each `R`). Case: main captures f0094 after B, then renames it to f0095, and the branch keeps an f0094 copy → red. Mutant: `--no-renames` dropped.
Lesson: tracker/item-history-spans-moves-and-compaction.

### F4 [low] The trust AC18 now puts in `origin` is not written down: `origin` is local configuration, and a swapped URL, a `url.*.insteadOf` or `GIT_CONFIG_*` in the environment makes any commit "published main"
Where: `rewrites.mainBase` (`git ls-remote origin refs/heads/main`); c0120.md Guess 18's "Main is the published one"; the testing skill's "Caught only by review" list.
Evidence: clone `atk`. Commit C (a weakened c0122 `check.sh`) is pushed to a bare repository I control. With `origin` pointed there by `remote set-url`, by a repo-local `url.<mine>.insteadOf`, or by `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.<mine>.insteadOf …` in the environment, AC18 is green each time (`main 393b65d2…`). The runner's tripwire sees config changes only during a run.
Critique: under the user's "detect, not prevent" this is a limit, not a hole: the URL is visible to whoever looks. Today nothing shows it, though, and the design text reads as if the published tip settled trust.
Recommendation: write the limit into Guess 18's paragraph and into the testing skill's "Caught only by review" list ("AC18 trusts the `origin` it resolves; a reviewer checks the URL it printed"). Print the resolved URL (`git ls-remote --get-url origin`) in AC18's green and red lines, so the reviewer's run shows it. Case: a fixture origin given via `insteadOf` → the line names the substituted URL.

### F5 [low] `mainBase` takes the first line of a tail-matched `ls-remote`: any branch whose name ends in `/refs/heads/main` and sorts before `main` makes AC18 refuse with a wrong reason
Where: `rewrites.mainBase`: `string.match(out, "^(%x+)%s+refs/heads/main")` on the whole output of `git ls-remote origin refs/heads/main`. git matches that pattern against each ref's tail, so `refs/heads/a/refs/heads/main` is listed too, and it sorts first.
Evidence: clone `atk`, after pushing `refs/heads/a/refs/heads/main` to its origin: `cannot read origin's main (git ls-remote origin refs/heads/main): refusing`. With `zz/refs/heads/main` it reads the right tip. Anyone who can push a branch can stall every AC18 run with a message that blames the network. It fails closed, so this is low.
Recommendation: scan every line for an exact `^(%x+)\trefs/heads/main$`, and refuse when there is not exactly one. Case: the look-alike branch in finished.spec's bare origin → still green, with the real tip.

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"). `git log --first-parent c601e77e..7a01bd47` holds only 39bee1d, 1925b4e, 42b1bef and 7a01bd4, and groups 1-5 are untouched.
  - 39bee1d is hand-written core: `z-nile/engine/audit.luau` and `z-nile/tests/tooling/audit-spec-left.spec.luau`, both Touched tooling. It does one thing, the audit's `spec-not-promoted`.
  - The three merges carry only prep files: c0120's folder and one review-lesson paragraph.
  - No commit mixes a move with an edit, and the group holds no override.

## Prep reference
Not recorded. Prep 6f6adf61's changes in c0120's folder since 676dfa8e (554b6c8, 16388e7, 6f6adf6) are the ones reviewed this round: `finished.luau`, `finished.spec.luau`, `override-markers.luau`, `rewrites.luau`, c0120.md's Guess 18 and Rules rows V26 to V28, harvest, review-008 and refute-008. Nothing in them is unreviewed. F1 and F2 are defects in AC18 itself, so this round doesn't pin the prep. For the next round: with a stub approving `review-009.md` that pins 6f6adf61, AC18 was green (251) on the fully merged tree, before and after c0114's `done`.

## Lesson candidates (for the lead)
- review/sequestration-reference-not-a-ref, an addition: a whole-main merge is proven by every gate, not only by the sequestration checks. Main's tooling rafts promote specs written for the old layout, which the move must override, and a sequestration check that forbids every edit to a spec main promoted has no room for those overrides. Check: after merging all of today's origin/main, do all gates *and* the sequestration check pass together?
- The same lesson, on derived inputs: anything a reference is computed from (a tree a rewrite consults, a commit picked by `git log -1 -- <path>`) is a reference too. Check: can a commit that later commits undo choose what this check expects?

Verdict: changes
