# Review 015: c0118 (design mode)
Inputs: prep-project-board c818ebd1 (c0118.md whole, check.sh, the seven acceptance specs, `acceptance/overrides.sh`, `acceptance/overrides.patch`, harvest.md, the three lesson notes of `git diff b306ed15 c818ebd1 -- z-nile/skills/`, design-review/refute 013 and 014); proto2-c0118 6bb217fb (`git ls-remote origin refs/heads/proto2-c0118` → 6bb217fb…); origin/main cbc8a969 (`git ls-remote origin refs/heads/main`). Scratch clones under `/private/tmp/claude-501/review-c0118-015/` (`git clone --no-hardlinks` of the prep worktree, origin URL set to `https://github.com/philipbergen/pickman.git` inside the clone only, identity `reviewer@scratch.local`): `r`, branch `raft` = cbc8a969 + a merge of c818ebd1 (2ee4e01d, the prep as it would land) + step 1's apply (5b7f6e2a); `r2`, a clone of `r`, for the AC9 windows, mutants and a simulated `done`. The window scripts are `/private/tmp/claude-501/review-c0118-015/bin/windows{,2,3}.sh`, run through `./zn run --time …`.
Dropped from design-review-014: none; F1–F5 rerun below and fixed as the refute says.

What was run, and held:
- Step 1: `git merge-base --is-ancestor 6bb217fb origin/proto2-c0118` rc 0; `git diff c1b429a9 6bb217fb -- <the 17> | git apply -3` → 17 × "Applied patch … cleanly" (history.luau via "Falling back to direct application"), rc 0; `git diff 6bb217fb --stat -- <the 17>` empty; `git log --first-parent c1b429a9..origin/main -- <the 17>` empty.
- `./zn check c0118` in `r`: **10/10** (1 min 20 s), with `AC9 reads origin's main from: https://github.com/philipbergen/pickman.git` printed beside AC9's PASS (014 F2 fixed).
- AC9 windows (`overrides.sh <tip>` in `r2`; "main" commits are local stand-ins with the tip passed as the argument; rc 0 = green):

  | window | rc | right? |
  |---|---|---|
  | W0 the raft vs origin/main | 0 | yes |
  | W1 main with the prep, branch cut, after `start`'s commit, nothing applied | 1 (all eight differ) | yes: red before the work |
  | W2 main appends a line to `c0042/smoke.spec`: not merged / merged | 0 / 0 | yes |
  | W3 c0239's real change (the RC0 substitution in `c0120/docs.spec` + its own `rehash.py`, `d5634735 -> ea2a9051`): not merged / merged | 0 / 0 | yes (013 F2 / 014 F1 hold) |
  | W4 the raft rebased onto W3's main | 0 | yes |
  | W5 squash landing (`commit-tree raft^{tree} -p cbc8a969`): on the raft / on main / a later branch off it | 0 / 0 "already part of main" / 1 "the reviewed hunks no longer apply" | yes / yes / dead after `done`, as the Test plan says |
  | W6 merge-commit landing | 0 "already part of main" | yes |
  | W7 merge W3's main and delete one `model.spec` assertion in the merge commit | 1 (`c0042/model.spec.luau`) | yes: an evil merge is caught |
  | W8 one `keep.spec` assertion deleted outside the hunks | 1 (`c0107/keep.spec.luau`) | yes |
  | code reviewer's `./zn sync --fetch` without merging | = W2/W3 not merged: 0 | yes |
  | c0123's real `board.spec` hunks (its `experiments/prototype.patch`) on main: not merged / merged | 0 / 0 | yes |
  | main changes `keep.spec` on other lines (and, as it must, c0172's pin of it) | not merged 0; merged: conflict in `narrowed.spec`, then rc 1 "the reviewed hunks no longer apply" | fail-closed, but see F1 |
  | c0239's or c0123's change as a co-member on the raft branch | 1 / 1 | by construction, see F1 |

  The exit-0 path: it fires only when HEAD is an ancestor of the tip read from origin, so the branch's author cannot make it fire while the branch holds commits main lacks (W1 red, W7 red); with a redirected origin it is reachable, which is the accepted detect-not-prevent limit and is printed. It does fire on an unimplemented tree that is in main (HEAD = main + the prep, before `start`): F2.
- Repository safety of `overrides.sh`: its writes are `mkdir -p z-nile/.cache`, a `mktemp -d` there, `git init` and the eight files in that fixture, `git apply` inside it, `rm -rf` of the fixture (set only after `mktemp` succeeded); the real repository gets `rev-parse`, `ls-remote`, `cat-file`, `merge-base`, `show`. Under ac.sh the ceiling includes `z-nile/.cache` and the fixture's own `.git` is found first. No commit, no identity, no ref. On the simulated `done` tree (acceptance moved to `z-nile/tests/acceptance/c0118`, folder to `issues/done/c0118`), `lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/acceptance/c0049/spec-isolation.spec.luau tests/acceptance/c0077/cache-paths.spec.luau tests/acceptance/c0120/check-paths.spec.luau tests/acceptance/c0120/finished.spec.luau tests/acceptance/c0047/override-check.spec.luau` → 34 passed, 0 failed: the reworded script trips no scanner.
- AC10: presence of one `real.spec\t*` line; M81 as recorded. AC_LIST mode prints the URL line between LIST lines; nothing parses that output (`grep -rn AC_LIST z-nile/engine z-nile/tests/lib` → only main.luau's refusal and fence.luau's comment).
- Full gate in `r` (main + prep + apply, this round's check.sh and overrides.sh in the tree): **GATE PASSED (full)**: pickman 1815 passed, 0 failed (269 files); z-nile 1621 passed, 0 failed (235 files); the five arcade homes 25/25 each; gate wall time 423.7 s (the `tests/unit/*` FAIL lines in the log are fixture output inside passing specs).
- Scope: `./zn capture c0118` (fb7fd805): title, Problem and Solution as captured; nothing dropped since 014.
- Lessons: the three notes added this round agree with each other and with the design (merge-base file plus the reviewed hunks; `git merge-base HEAD <tip>`; the URL printed outside `check`). One gap, F1's lesson candidate.

### F1 [low] The execution window misses three cases the merge-base form leaves red for good: c0123 (a prepared chore with no raft) changes `board.spec` and is not named; any co-member of c0118's raft that changes one of the eight files makes AC9 red by construction; and main's change to any line of `keep.spec` forces a re-prep, which the step 1 conflict rule says is allowed
Where: Implementation step 1 "Reviewed overrides" (names c0239 only) and "Conflict rule" ("A conflict in the eight reviewed specs is allowed too when upstream's side is a change to other lines of the file (resolve by keeping both), and AC9 judges the result"); G9 ("z-raft may raft it … with another prepared chore"); design-review-014's evidence ("only c0239 edits one").
Evidence:
```
$ git grep -l -E 'c0107/(keep|page|views)\.spec|c0042/(model|smoke)\.spec|c0115/readme\.spec|c0172/narrowed\.spec|tooling/board\.spec' origin/main -- '*/.tracker/issues/*' '*/.tracker/rafts/*' | grep -v /done/ | grep -v /c0118/ | awk -F/ '{print $4"/"$5}' | sort -u
c0083/acceptance  c0083/c0083.md  c0083/experiments  c0121/c0121.md  c0121/check.sh  c0121/prototype.patch
c0123/check.sh  c0123/experiments  c0180/design-review-003.md  c0239/acceptance  c0239/c0239.md  c0239/design-review-001.md  R0030/…
$ sed -n 2162,2166p z-nile/.tracker/issues/c0123/experiments/prototype.patch
diff --git a/z-nile/tests/tooling/board.spec.luau b/z-nile/tests/tooling/board.spec.luau
index 653adfc4..e3b10b13 100644
```
c0123 is `type: chore`, `raft:` empty, `status: prepared-…`, and its Overrides text says "`lock-start-ids`, `start-pr-reuse` and `board` also rename their stub folders". Run (windows3.sh): c0123's board.spec hunks on main, then merged into the raft: rc 0 (the hunks are 7+ lines from c0118's); the same hunks committed on the raft branch as a co-member: `[coraft-c0123] rc=1 AC9: differs from the merge base plus the reviewed hunks: z-nile/tests/tooling/board.spec.luau`; c0239's change as a co-member: `[coraft-c0239] rc=1 … c0172/narrowed.spec.luau`. And (windows2.sh) main appending one comment line to `keep.spec` and moving c0172's pin to the new digest, as any change to keep.spec on main must: not merged rc 0; merged: `merge rc=1 conflicts: z-nile/tests/acceptance/c0172/narrowed.spec.luau`, and with the row set to the merged keep.spec's digest (what c0172's spec then needs) `rc=1 error: patch failed: z-nile/tests/acceptance/c0172/narrowed.spec.luau:58 … AC9: the reviewed hunks no longer apply to the merge base 5d214b85…`.
Critique: every case fails closed, so none passes a wrong tree; but each ends in a re-prep after the raft has run, and nothing tells z-raft or the executor beforehand. The narrowed hunk replaces a digest of keep.spec's whole text, so "other lines" of keep.spec are lines c0118 overrides in effect; the conflict rule's allowance is untrue for that one file. A co-member's change to one of the eight can never pass, since the executor may not extend the sequestered `overrides.patch`. Today the risk is small: by z-raft's fixed policy c0118 (1350) and c0123 (1200) exceed the ~1,500-line cap together, and R0086 (c0239, no `size:`) takes nothing; a raft made with arguments can still pair them.
Consequences: naming the constraint puts it in z-raft's coherence review (item 7) and the executor's stop conditions; it doesn't change AC9. The other way, writing the co-member's hunks into the patch, needs a reviewed edit of the patch per pairing: not recommended.
Recommendation: in "Reviewed overrides", name c0123 beside c0239 (prepared chore, `board.spec` stub folders, no overlap with the hunks, merged rc 0); add to G9 (or a Raft note) "never in one raft with an item that changes one of the eight files (c0123, c0239 today): AC9 is red by construction"; and in the conflict rule, except `keep.spec`: any change main makes to it moves c0172's pin row, which the patch changes, so it stops the step (and, after the cut, AC9 is red: re-prep). The searches above go in the Verification log.
Lesson: z-design/design-the-execution-window

### F2 [low] AC9's "passes with a note" shows no note, and AC9 passes on an unimplemented tree that is in main
Where: AC9 ("passes with a note when the branch is already in main"); step 1 "Reviewed overrides" ("when the branch is already part of main it says so and passes"); overrides.sh lines 14–17 (the note goes to stderr inside `check`).
Evidence: in `r2`, detached at 2ee4e01d (main + the prep, no `start`, nothing applied):
```
$ ./zn run --time 120 -- bash -c 'source z-nile/lib/ac.sh; check "AC9 probe" bash "$ZN_ROOT/z-nile/.tracker/issues/c0118/acceptance/overrides.sh" "$(git rev-parse HEAD)"; finish'
PASS  AC9 probe
---- 1/1 criteria passed
```
The note "AC9: this branch is already part of main …: nothing left to judge" shows only when the script is run bare (W5, W6). ac.sh's `check` keeps a passing command's output to itself (`if out=$("$@" 2>&1); then printf 'PASS  %s\n'`), the same reason 014 F2 moved the URL line out of `check`.
Critique: harmless where it matters (the raft branch, W1 red), but the main checkout's `./zn check c0118` after the prep lands, or a worktree cut before `start`, shows AC9 PASS on a tree with none of the overrides, and the document says a note explains it.
Consequences: printing the note outside `check` needs the ancestry test in check.sh too (`git merge-base --is-ancestor HEAD <tip>` needs the network call for the tip); cheaper to fix the words.
Recommendation: say in AC9 and step 1 "passes silently (`check` hides the script's note) when HEAD is already in main, which on a branch with commits of its own means the raft landed"; no new mutant needed (W1, after `start`, is red).
Lesson: z-design/restated-rules-move-together

### F3 [low] Text the round left untrue
Where: Rules and mutants header (line 320) and row M78 (line 389); G11 (line 476); step 7 (line 444); Verification log, "Design review 014 answered" (line 510).
Evidence: `grep -n -F "main's file plus" c0118.md` → line 389 ("each overridden spec is main's file plus the reviewed hunks, nothing else") and line 476 ("AC9 judges keep.spec and the other seven overridden specs as main's file plus the reviewed hunks"), the tip form 014 F1 retired. Line 444: "they are the prototype's text (AC9)", untrue once main has changed one of the eight (W2, W3: the merge base's text plus the hunks). Line 510 ends "the prep's final gate is below" and nothing follows (line 511 is blank, the file ends). Line 320: "All rows `run`", while M83, M89 and the last row are `reasoned`. The lesson exact-checks-compare-against-the-merge-base says "print the URL … resolved with the base", its new note and the design print the URL only (the base only on failure).
Critique: the reader of G11 and row M78 learns the form this round dropped; the log promises a gate run it doesn't record.
Consequences: none.
Recommendation: "the merge base's file plus the reviewed hunks" in both places; step 7 "the merge base's text plus the reviewed hunks (AC9)"; record the final gate in line 510 (this review's run: GATE PASSED (full), z-nile 1621/0, 423.7 s); "Rows `run` unless marked `reasoned`"; in the lesson's note say the base is printed in the failure messages and why the URL alone is printed on a pass (the tip needs the network), or print the base too.
Lesson: z-design/restated-rules-move-together

## Lesson candidates (for the lead)
- zz-test (narrowing-pins-the-whole-file) or z-design (design-the-execution-window): when an override changes a digest that pins another file whole, the digest row is coupled to every line of the pinned file: any change main makes to that file, on any line, moves the row and stops the merge-base check. Check: does the design's conflict rule treat the pinned file's "other lines" as overridden lines?
- z-design (design-the-execution-window): an exact check on a file ("base plus these hunks, nothing else") forbids any co-member of the raft from changing it. Check: does the design name the open items that change the judged files, and say they may not share its raft?

Verdict: approve
