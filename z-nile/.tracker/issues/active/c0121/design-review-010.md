# Review 010: c0121 (design mode)
Inputs: prep-board-server 2f1cfa9a (c0121.md whole, check.sh, `acceptance/overrides.sh`, `acceptance/overrides.patch`, harvest.md, design-review-009 and design-refute-009, `git diff HEAD~1 HEAD`); proto2-c0121 fa44f524 (`git ls-remote origin refs/heads/proto2-c0121` → fa44f524…); origin/main 47e6d0d8 after `git fetch origin main` (since 3993dca2 it changed tracker files only: `git diff --name-only 3993dca2 origin/main | grep -v '\.tracker/'` → nothing). Scratch clone `.worktree/prep-board-server/.cache/r010/repo` (round 009's setup with `PREP=2f1cfa9a` and identity `reviewer@r010.local`: `main` = origin/main + the prep's c0121 folder, `raft` = main + an empty start commit + step 1's apply, origin set to the clone itself, push URL `/dev/null`); a throwaway repository `.cache/r010/tags` for the index-flag probes. Probe scripts `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r010-{setup,tags,replace,flags}.sh`, each through `./zn run --time …`.
Round 5 of the re-prep (G8), the final round. Dropped from design-review-009: F1 (the refutation is right: see the ruling below; its leftover wording is part of F3 here), F2 (fixed), F3 (fixed and run, below), F4 (fixed, apart from line 251: F3 here), F5 (fixed).

## Rulings on round 4's answers
- **009 F1, refuted ("the code review's job"): the refutation holds.** The code review reads `git diff origin/main...HEAD`, which shows every changed line of the three owned files. A shape check for `loops.luau` would be a new mechanism, written against a registry that isn't on `main` yet, with failure modes of its own. One half of 009 F1's alternative wasn't done: AC7's text still claims "(its entry for `serve.luau`'s retry wait)" as if the check judged it (F3).
- **009 F3, fixed with the `ls-files -v` check: holds; one hole of the same class is left (F2).** Run in `.cache/r010/tags` (git 2.54.0), with the regex `^[a-zS] ` over `git ls-files -v -- ':(glob)*/tests/**'`:
  - The tags printed: skip-worktree `S`; assume-unchanged `h`; both flags `h` (lowercase wins, so it matches); intent-to-add (`git add -N`), a deleted file and a modified file `H`; an unmerged entry during a merge `M` ×3; a gitlink `H`.
  - Names with spaces print bare (`H z-nile/tests/sp ace/t ab.luau`), and a name with a tab prints quoted (`H "z-nile/tests/lib/tab\tname.luau"`). The tag is still the first byte in both cases, so neither name breaks the match.
  - A cone sparse checkout that leaves `lib/` out tags every file outside the cone `S`, so it is red with the message, which fails closed. `core.fsmonitor=true` and a split index print no lowercase: no wrong red. `core.ignorestat=true` makes newly added files `h`, so it is red. Nothing in the repository sets it, nor `skip-worktree`, `assume-unchanged` or a sparse checkout on a worktree: `git grep -n -E 'skip-worktree|assume-unchanged|sparse-checkout|ignore[sS]tat|update-index'` outside done items finds only fixtures, c0178's sparse clones of spec fixtures (under `.cache`), and its prototype. `git config --get-regexp 'core\.(fsmonitor|ignorestat|sparsecheckout)…'` is empty. This worktree and the main checkout have 0 flagged entries, and the repository has 0 gitlinks.
  - None of these states wrongly turns AC7 green. The unmerged `M` doesn't match the regex, but in the middle of a merge the scope diff is red anyway, and nobody expects green there. An intent-to-add file shows in `--raw` as `A` (red, correct: c0121 adds no test file). A gitlink under `tests/` shows as `A 160000` when its folder exists. When its folder doesn't exist it is invisible to the working-tree diff, but `git status` shows ` D`, which `./zn done` refuses (main.luau:4109).
  - M15 and M16 rerun on today's `raft` (`r010-flags.sh`): a committed `-- evil` on `docs.spec` and on `c0118/page.spec`, then the flag set and the working tree restored, so `git status` is empty. `skip-worktree` gives rc 1 on each file and `assume-unchanged` gives rc 1 on each file ("test files hidden from git's working-tree view"). The flag alone on `cachepaths.luau`, with no edit, gives rc 1 (fails closed). Base and after: rc 0.

## What holds (run)
- **Step 1 replayed on today's main** (`r010-setup.sh`):
  - `merge-base --is-ancestor fa44f524 origin/proto2-c0121` succeeds.
  - Every non-new watched path exists on main, and `serve.luau` doesn't.
  - `git log --first-parent 3993dca2..origin/main -- <watched paths>` prints nothing.
  - `git diff 3993dca2 fa44f524 -- <8 paths> | git apply -3` exits 0 with every path clean.
  - `git diff fa44f524 HEAD -- <8 paths>` is 0 lines.
- **`./zn check c0121` on the replayed raft: 7/7** in 28 s (AC7 prints the clone's own path as origin).
- **c0117's contract greps** on `git show origin/main:z-nile/engine/dispatcher.luau` (byte-equal to 3993dca2's, `cmp`):
  - (1) `73: follows: string?, …` and `1848: st.follows = action.target`.
  - (2) exactly `986: … = cwd, now(), "running", mode`.
  - (3) `failed` 8, `lost` 1, `missing` 1, `stopped` 1, `tripwire` 7; the `nil` clears at 1790 and 2044; `ok` at 1178.
  
  Every hit matches what the step expects.
- **c0120 `check-paths.spec`** from `z-nile/` in the prep: 4 passed, 0 failed.
- **The in-flight search** (step 1's `git grep -l -E 'engine/board\.(luau|html)|…|c0118/docs\.spec' origin/main -- '*/.tracker/issues/*' '*/.tracker/rafts/*'` outside `done/` and `retired/`) returns the same item set on 47e6d0d8 as on 3993dca2. The only difference is that c0269 is now `active/`, and it only mentions the watched files (round 009's `awk` over Touched modules). The twelve named items, c0181 among them, still count twelve.
- **`./zn done` runs check.sh before it promotes** (main.luau:4116 `runCheck`; the promotion starts at :4121), so AC7's "nothing new under `tests/`" doesn't trip on c0121's own promoted folder at `done`.
- **No spec lives outside a project's `tests/`** except the tracker's own acceptance specs: `git ls-files | grep '\.spec\.luau$' | grep -v -E '^[^/]+/tests/' | grep -v '\.tracker/'` → nothing, and there is no top-level `tests/`. So `:(glob)*/tests/**` is the whole test surface, and `**` also reaches deeper `tests/` folders (`z-nile/tests/deep/x/tests/q.luau` matched in the probe repo).
- **After the 7/7 run the clone is clean** (`git status --porcelain --ignored -- '*/tests/**'` is empty), so the gate's specs leave nothing under `tests/` that would turn AC7 red.
- **Scope**: `git diff HEAD~1 HEAD -- c0121.md` touches no Problem, title or Solution line.
- **Repository safety**: the new `ls-files -v` read is read-only. overrides.sh still writes only `$TOP/z-nile/.cache/c0121-ac7.*`, its own `git init`, which its trap removes.

### F1 [medium] AC7 refuses every new test file, and no step says what the raft does when its code review asks for a test case
Where: acceptance/overrides.sh:50, :59-62 (any untracked file under `tests/` is red) and :63-71 (any `A`, or any `M` outside the three owned files, is red); c0121.md:326 ("nothing under `tests/` is new or untracked"); c0121.md:343-349 (steps 2 to 7 name no spec of the raft's own); c0121.md:339 (the only route given is R0074's, and it covers lessons only); z-nile/skills/zz-execute/SKILL.md:30-31 ("Write the specs in the issue's Test plan under `tests/`. These are your own unit, contract and regression specs."); zz-review Code mode ("A code-mode Recommendation never asks the author to edit sequestered … acceptance specs … If that's the only fix, say the author must escalate").
Evidence: on today's replayed `raft` I added an own regression spec, `z-nile/tests/tooling/serve.spec.luau`:
- untracked: rc 1, `AC7: untracked files under tests/ (c0121 adds none before done): z-nile/tests/tooling/serve.spec.luau`;
- committed: rc 1, `AC7: changes a test file it does not own, or not in place (A 000000 100644): …`.

c0121's code is about 580 new lines: a server, a guard and a dispatcher bridge. Its only tests are the sequestered specs, which the raft may not edit. Code-mode reviews here routinely recommend a new case in an unsequestered spec; R0081 review-005 F2 and review-006 F2 each prescribe a case in `tests/tooling/reuse-e2e.spec.luau`. For this raft, any finding of the kind "a missing test for an edge case" (the severity table's own example of a medium) or "fix X and pin it" has no answer:
- the test can't go in the sequestered specs;
- AC7 refuses it anywhere else;
- the code review can't approve while the finding stands.

So the raft stops and escalates for something the prep can decide now. The rule came from 007 F2 (widened from "no other promoted or tooling spec is edited" to "nothing new under `tests/`"). No round weighed the raft's own tests (`grep -n -i -E "own (unit|spec|regression)|tests first|code review|new test" design-review-00[6-9].md design-refute-00[6-9].md` → no hit on this question).
Critique: two fixes are tempting, and both fail:
- Dropping the "nothing new" rule reopens M9 and M10: a spec moved into `tests/acceptance/c0121/` before `done`, which collides with the promotion.
- Telling the executor to skip the test leaves the code review's finding unanswered.

This is the third time AC7's scope rule has met work the raft must do (008 F1 `loops.luau`, 009 F5 R0074's lessons, now the raft's own specs). The rule names what the raft may touch, so every legitimate need has to be foreseen and listed.
Consequences: an owned new-file path is new state for AC7. It must not exist on `main`, as `serve.luau` must not, or the "new" status means nothing. It needs a status (`A`), a mode (100644) and the untracked form. A new file can't weaken an existing spec. The gate runs it, and it is promoted nowhere.
Recommendation: decide the route in the design and pin it. Either option keeps every captured outcome; (a) also keeps the code review able to close a test finding inside the raft.
- **(a)** Give the raft one owned new spec: `z-nile/tests/tooling/serve.spec.luau`, its own unit and regression cases for `serve.luau`.
  - List it in Touched modules and in AC7's text.
  - In overrides.sh, accept that one path as `A` with mode `100644` (and untracked before the commit).
  - In step 1's watched paths, check it doesn't exist on `origin/main` (`git cat-file -e`).
  - Rows: that file new → rc 0; that file executable or a symlink → rc 1; any other new file (M10, M12) → rc 1.
- **(b)** State in the Implementation steps and in the prompt-facing text that the raft adds no test file. A code-review finding that needs a new case is answered by a capture (`./zn new issue …`) landed after c0121 and named in the refute. The code reviewer is told the same, so it rules on that capture instead of holding the PR.

### F2 [low] A local `git replace` of the merge base's `docs.spec` blob passes a weakened override through AC7 and blinds the local three-dot diff the code review reads
Where: acceptance/overrides.sh:31 (`git show "$BASE:$f"`), :49 (`git diff … "$BASE"`); overrides.sh's header (:4-6 names only the origin URL as its trust limit).
Evidence (`r010-replace.sh`, on today's `raft`):
1. Drop line 105 of `docs.spec`'s assertions (`t.expect(projects > 1).toBe(true)`), keeping the override, and commit: rc 1.
2. Then `git replace <base blob d7cf6cfa> <HEAD's file with the hunk reversed>`: rc 0.
3. `git diff main...HEAD -- docs.spec` now shows only the reviewed one-line hunk, and the dropped assertion is invisible. `refs/replace` sits in the common git directory, so every worktree on this machine sees the same false view, the code reviewer's included.
4. `GIT_NO_REPLACE_OBJECTS=1 bash overrides.sh main`: rc 1.

Critique: this is the same class as M15 and M16, a deliberate falsification of git's local view, so it is low. The backstop is the PR's diff on GitHub, because replace refs aren't pushed by default. But rounds 3, 4 and 5 have each found the next way to falsify the local view: hidden flags, then replace objects. Shims are next (a `git` earlier on `PATH`, `GIT_DIR` or `GIT_INDEX_FILE` in the environment). The problem is the unstated trust boundary, not this one hole.
Consequences: the one-line fix costs nothing for honest work, since no tool here creates replace refs (`git for-each-ref refs/replace` → 0 in the clone). A header sentence ends the series.
Recommendation: add `export GIT_NO_REPLACE_OBJECTS=1` at the top of overrides.sh, with a row M17 (the probe above, rc 1). Then state the boundary in the header beside the URL sentence: "AC7 trusts this machine's git (its binary, environment and object store); it refuses the cheap hidings (index flags, replace objects) and leaves a deliberately falsified local git to the PR's diff on GitHub."

### F3 [low] AC7's text and two mutation-check lines disagree with the script and the table after round 4
Where:
- c0121.md:326 (AC7) has no clause for the hidden-flag rule and still says "`tests/lib/loops.luau` (its entry for `serve.luau`'s retry wait)".
- c0121.md:251 says "M1 to M13 the rebuilt one".
- c0121.md:186 says "M13 and M14 ran in design reviews 008 and 009".
- design-refute-009.md:1 says "The design records this in the Verification log".

Evidence: overrides.sh:51-58 refuses `S` and lowercase tags, which AC7, the Checked criterion, never mentions. The 009 F1 refutation leaves the content of an owned file's edit to the code review, yet AC7 still names the entry as if the check judged it.

Line 251 says every `run` row was applied to the rebuilt prototype for M1 to M13. In fact:
- M13 was run by reviewer 008 and M14 by reviewer 009, each in a scratch tree;
- M15 and M16 were run by the author (refute 009) and aren't in that sentence;
- line 186 lists M13 and M14 but not M15 and M16.

The "shape left to the code review" sentence is in Unknowns & experiments (:186), not in the Verification log the refute cites.
Critique: AC7 is what the executor and the code reviewer read as the rule. A rule that only the script states, and an entry that only the text claims, are what restated-rules-move-together warns about.
Consequences: none.
Recommendation:
- AC7: add "and no test file carries an `assume-unchanged` or `skip-worktree` flag (`git ls-files -v`)". Replace "(its entry for `serve.luau`'s retry wait)" with "(c0121's one entry; what an owned file's edit says is the code review's)".
- Line 251: "(N1 to N51 the first prep's; M1 to M12 and M15, M16 on the rebuilt one; M13, M14 by design reviews 008 and 009)".
- Line 186: add M15 and M16.
- Add M17 if F2's line is taken.

Lesson: z-design/restated-rules-move-together

## Lesson candidates (for the lead)
- z-design (design-the-execution-window): a check that lists what a raft may touch must also list what the raft's protocol makes it write. That means its own specs (zz-execute Phase 2 "your own unit, contract and regression specs"), the code review's test cases and the harvest's codified lessons, not only the in-flight items. Check: run zz-execute's steps against the allow-list. Which of them writes a file the check refuses?
- zz-review (run-the-evidence-you-cite): a check that judges git's local view (index flags, the object store, `refs/replace`) is blinded by the same falsification that blinds the reviewer's own `git diff`. When a round finds a hiding hole, state the trust boundary instead of closing holes one round at a time. Check: does the reviewer's own evidence read through the same local git the hole falsifies?

Verdict: changes
