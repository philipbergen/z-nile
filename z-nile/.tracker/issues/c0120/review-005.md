# Review 005: c0120 (code mode; the coordinator's round 002 of #107)
Inputs: `origin/impl2-c0120` at 61488eb7 (PR #107). Fix delta `git log --first-parent 41d5fa15..61488eb7`: dd124f70, 7dd43cde, 1605944a, cc03d317, 17acbd7d, 3b74b24d, 2d748497, b4b0f83c, 95788496, bc244e72, 093f22d1, 61488eb7, plus the prep merges f4d80f03, b28b47dc, b930cbeb, b44ef566, b100a377, ce4d21ec (prep `origin/prep-c0120` adbb1188). Read first: review-004, refute-004, c0120.md, design reviews 001-005 and their refutes, `./zn lessons --when build --full`, `./zn lessons --skill review --full`. Every run was in scratch clones under this folder. Nothing was run in the real repository or its `.worktree/*`.
Dropped from review-004: none. Every finding there is answered: F1 by Guess 18; F2, F3 (for the runner and the gate), F4, F5, F6 and F7 as the refute says. The checks are below. F2 here is F3's class again, in `ac.sh`.
The user's decisions applied: "Reviewer-pinned commit" (AC18) and "Reviewed by commit group" (the earlier groups are untouched, and the new commits are judged as one group of their own).

## What was run
- **Gates**, each in its own clone at 61488eb7:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1161/173, z-nile 839/121, 171.7 s.
  - `pickman/check.sh --full`: GATE PASSED. 1161/173.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 839/121, 168.3 s.
- **c0120's `check.sh`** (`./zn check c0120`): 15/18, and each red is red for its stated reason.
  - AC11: only `z-nile/.tracker/issues/c0114/check.sh: tracker/next` and `z-nile/next (from z-nile)`. c0114 is unfinished.
  - AC16: only `busy: cannot read origin/main`. origin/main (b7a027a2) has no registry.
  - AC18: refuses with `no approved review … records a "Prep reference: <sha>"`, as Guess 18 designs.
- **AC18 with a review in place.** In a clone, I placed an approving `z-nile/.tracker/issues/c0120/review-005.md` with `Prep reference: adbb11883ecb2a103a396e14fa2191d37573f309` and ran `lune run …/finished.luau -- <top>`. Result: `221 sequestered files are their text before the move … c0120's own as review-005.md records them`, which is green. adbb1188 is an ancestor of HEAD, and `git diff adbb1188 HEAD -- z-nile/.tracker/issues/c0120` is empty. With this file (Verdict: changes) in its place, AC18 refuses, by design.
- **`override-markers.luau -- f83441d6`**: all 922 hunks are marked (within 3 lines). cc03d317 and 17acbd7d add only marker lines. The one exception: 4 files whose multi-line `t.expect(` stylua reflowed once a marker sat inside it. The reflow is semantically identical.
- **Promotion dry run.** I copied c0120's acceptance folder into `z-nile/tests/acceptance/c0120/` and ran `z-nile/check.sh --full`. Every static stage passed: format, selene, luau-lsp (0 errors), and repo-fence from both homes. The tests gave pickman 1161/173 and z-nile 942/135 with 1 failure: the promoted check-paths live case, for c0114's two paths only. That is AC11's expected red, and it goes once c0114 is done.
- **The prep reference.** At adbb1188, c0120's folder is as follows:
  - Design reviews 001-005 cover the design up to 96075f83.
  - The answer to design review 005, Guess 17's rewrite rules and deletions, and AC18's first own-files rule (96075f83..7871a51b) were code review 004's base, and that round re-ran and attacked them.
  - The rest is 7871a51b..adbb1188, which this round reviewed line by line: Guess 18's `recorded()` and its spec case, the runner-home cases for F3/F6, `override-markers.luau`, the type fixes in docs, graph-homes, layout and finished (`(…)` around multi-returns and a typed pair: semantics unchanged), the review skill's `Prep reference` sentence, and harvest, lessons and refute-004.
  - Nothing in the folder is unreviewed. But F1 below is a defect in AC18 itself, so this round does not record the reference.
- **Repository safety (item 8).** I used clone `mac` (as shipped, jailed) and clone `lin` (`jail()` patched to the non-macOS branch: no kernel jail, hooks set). I took a fingerprint (refs, index, config, worktrees, HEAD) before and after every attack. It never changed, apart from the one demonstration in F2, which I reverted.
  - **Every home's fence (the runner).** I ran the probe spec from `pickman/` and from `z-nile/`. The ceiling names `<top>/.cache`, the other home's `.cache` and the run's own. git finds no repository in any of the three `.cache` folders or below them. `update-ref` and `commit` into the clone are refused (EPERM under the jail, the reference-transaction hook in `lin`). `pickman_guarded` answers `guarded`. All **closed** in both clones. Review-004 F3 is closed.
  - **Inherited environment into the runner.** I passed `GIT_DIR` (the clone's `.git`, a relative `.git`, a foreign repository), `GIT_COMMON_DIR` (foreign) and `GIT_CEILING_DIRECTORIES` (the root, and root:home), from both homes, in both clones: 24 runs, 0 open.
  - **The runner's refusals**, 20 runs, all of which refuse before any spec runs: a symlinked `.cache` at the other home, at the run's own home and at the root; a folder at the other home's sentinel; an unwritable other-home `.cache` with no sentinel in an honest environment. Nothing was written through a link.
  - **The runner's registry-home rule.** It refuses from the root (relative and absolute runner paths), from `scripts/` (absolute and `../z-nile/tests/run`), from `pickman/src` and from `z-nile/engine`. None of them made a `.cache` there. It runs from `pickman/` and `z-nile/` with `../z-nile/tests/run`, and from `pickman/` with `../pickman/tests/run`. Review-004 F6 is closed.
  - **The gate's home-cache refusals.** In 30 runs I tried a symlinked `.cache` and a folder at `.cache/.git` in `pickman/`, in `z-nile/` and at the root, each with `--plan`, `--project pickman --plan`, `--project z-nile --plan`, `--project pickman --full` and `--full`. Every home case refuses in every mode, before any stage or plan line, including a bad `z-nile/.cache` under `--project pickman`. A bad root `.cache` refuses `--full` but not `--plan` (F3).
  - **check.sh probes**, from the root, `pickman/` and `z-nile/`, for an item in each project, honest and with inherited `GIT_DIR`, `GIT_COMMON_DIR` and ceiling, in both clones. Everything was closed except the other home's `.cache`, which is open in both clones (F2).

### F1 [high] AC18 never sees a deleted sequestered file, so deleting one passes the criterion
Where: `z-nile/.tracker/issues/c0120/acceptance/finished.luau`, the main loop. It walks `git ls-files` of HEAD's roots and judges each file against `pre` or the recorded reference. It never walks the other way.
Evidence: in a clone at 61488eb7 with an approving review in place, AC18 printed `221 … are their text before the move`. Then:
- `git rm` of c0120's own `acceptance/runner-home.spec.luau` gave `finished: 220 sequestered files are their text before the move …`, which is green.
- `git rm` of `pickman/.tracker/issues/active/f0065/check.sh` and `z-nile/.tracker/issues/done/c0001/check.sh` gave `219 …`, also green. `./zn audit` also stays at 0 errors without f0065's `check.sh`.

The same blind spot covers a file added to c0120's own folder beyond the reference: `okOld` is false, so the file isn't judged. The review skill's item 2 can't stand in for AC18 here. `git diff -M100% origin/main...HEAD` over the sequestered globs lists 161 A and 133 D lines on this branch, because c0114's move isn't on main, so a deletion hides among them. Nothing has slipped today: every one of the 221 pre-move files exists at its new place at HEAD, and c0120's folder equals adbb1188's.
Critique: AC18 is the only mechanical sequestration check this branch has, and a review round already found one hole in its reference (review-004 F1). It answers "is every file here unchanged?" but not "is every file still here?". The tempting fix is to also loop over `pre`'s file list and require each one at `before⁻¹(path)`.
Consequences: a file legitimately moves after the move when a merge of main finishes a raft (`issues/active/X` → `issues/done/X`) or compacts or renumbers an item. A path-keyed reverse walk would call that a deletion. Today the forward walk silently skips such a file: `before(path)` at `pre` is missing, so `okOld` is false, which is a second blind spot. Both directions need the item's identity, not its path. For c0120's own folder the reference is exact, so the set can be checked exactly.
Recommendation: fix it in prep, as Guess 18 allows for c0120's own files; the next approving review pins it. Escalate only if the lead reads this as changing the criterion; its text ("every item's check.sh and acceptance file … is its text before the move") already covers presence. The fix:
- (a) Key every sequestered file by (item id, path inside the item folder). Find each one at HEAD in any state folder of its root. A file at `pre` that isn't at HEAD is `deleted`.
- (b) A file at HEAD whose item existed at `pre` but which wasn't there is `added`. This applies to c0120's own folder against the reference too. A capture since the move stays exempt.
- (c) Judge a file whose item changed state since `pre` against its text at `pre` under the old state. If it lands in `done/` and is a `check.sh`, the rewrite applies (or c0114's `finished`-style fixed list, whichever the design prefers).

Spec cases in `finished.spec`'s own-files fixture:
- `git rm` of c0120's `check.sh` → red, `deleted`;
- a new `acceptance/x.spec.luau` in c0120's folder → red, `added`;
- an unfinished item moved to `done/` by a later commit, unchanged → green;
- the same item with its spec edited → red.

Mutants: the reverse walk dropped; identity by path instead of id.
Lesson: review/sequestration-reference-not-a-ref (same mechanism; see the candidate below).

### F2 [medium] (repeat of review-004 F3's class, in `ac.sh`) A `check.sh` fences the root and its own home, never the other homes, so git in another home's `.cache` finds the real repository
Where: `z-nile/lib/ac.sh` lines 35 and 70-72 (`pickman_home_fence` for the root, then for `$_ac_home` only). dd124f70 gave the runner and the gate every registry home, but not `ac.sh`.
Evidence: in clone `mac` (macOS as shipped; `check.sh` files run unjailed everywhere), I removed `z-nile/.cache/.git`. That is the state of a fresh checkout, or of one where no z-nile run has happened since `.cache` was cleared. A pickman `check.sh` run from the root or from `pickman/` printed `CEIL=$D/.cache:$D/pickman/.cache`. In `z-nile/.cache` and in `z-nile/.cache/atk5`, `git rev-parse --absolute-git-dir` printed `$D/.git`. A pickman `check.sh` whose criterion was `mkdir -p "$ZN_ROOT/z-nile/.cache/atk9" && cd … && git add -f -N f` PASSED, and the clone's index gained `z-nile/.cache/atk9/f`; the fingerprint changed from 259434904669 to e290d28b77aa. I reverted it with `git rm --cached`, and the fingerprint is back. The ref guard held: `commit` and `update-ref` are refused by the hook. No current unfinished `check.sh` writes into another home's `.cache` (grep).
Critique: this is the same hand-listed set that review-004 F3 found in the runner. The lesson written for it ("Every home, not a hand-listed set") was applied to `fence.enter` and the gate, not to the third guard set. The obvious fix is to copy the runner's loop into `ac.sh`. The next guard set added would then miss it again.
Consequences:
- `ac.sh` writes the other homes' sentinels before any `check`. That is harmless next to a concurrent run (a rename of the same content).
- Inside a jailed spec run that starts a `check.sh` (a fixture's), those writes fall under the same marker waiver the root's already uses.
- The registry is read twice: once in `ac.sh` (`z-nile/roots -- --projects`, which `ac.sh` already runs), once in `fence.luau`.
Recommendation:
- Give `fence.sh` one function, e.g. `pickman_fence_all <top> <own home>`: refusals, ceiling and sentinel for the root and every home that `z-nile/roots -- --projects` lists. Have `ac.sh`, `fence.enter` (through its bash step) and the gate call it, so the set has one owner.
- Add a tooling spec, not a sequestered one, that runs a fixture `check.sh` of each project from the root and from each home. git in every other home's `.cache` and below finds no repository, and a symlinked other-home `.cache` refuses. Run it with `PICKMAN_TEST_JAIL` set to `sandbox-exec` and to `none (…)` (lesson testing/specs-set-host-markers-explicitly).
- Add a repo-fence or meta case that every caller of the fence in `z-nile/` uses that function.
Lesson: testing/guards-move-with-the-working-directory.

### F3 [low] gate-home-cache seeds only `pickman/.cache`, so a gate that refuses only the first home passes it
Where: `z-nile/tests/tooling/gate-home-cache.spec.luau`; `z-nile/check.sh:98` (`for i in "${!names[@]}"`).
Evidence: I changed the loop to `for i in 0; do` (the first registry home only). Result: `gate-home-cache.spec.luau`: 1 passed, 0 failed. Separately, a symlinked root `.cache`, or a folder at its sentinel, passes `--plan`: the root's refusals come after the plan. `--plan` writes nothing, so nothing leaks.
Recommendation: also run the case with a symlinked `z-nile/.cache`, under `--project pickman --plan` (a home the selection doesn't pick). Either refuse a bad root `.cache` before `--plan` too, or say in the header that only the homes are checked there.
Lesson: testing/seed-every-enumerated-case.

### F4 [low] repo-fence's key check accepts a key under the wrong home, and an untracked file
Where: `z-nile/tests/tooling/repo-fence.spec.luau`, "every allow-list key names a file, or an unfinished item's spec where done will promote it".
Evidence: by reading, a key `pickman/tests/acceptance/c0120/homes.spec.luau` passes. Its id and file match `z-nile/.tracker/issues/c0120/acceptance/homes.spec.luau` in some root, but `done` promotes c0120 into `z-nile/tests/…`, so the key never matches the scan. That is review-004 F2's defect again. `fs.isFile` also accepts an untracked file, while the comment says "tracked".
Recommendation: map the root where the item was found to its home (the registry, `projects.homeOf`), and require the key's prefix to be that home. Check tracked files with `git ls-files`. Add a planted wrong-home key as a mutant.

### F5 [low] AC18 counts a review as approving when any line starts with `Verdict: approve`, not when its verdict does
Where: `finished.luau` `recorded()`, `string.find(text, "\nVerdict: approve", 1, true)`.
Evidence: by reading, a `changes` review that quotes the format block or an earlier verdict at the start of a line (as the review skill's template does) counts as approved. Its `Prep reference:` line, if it has one, is then read. That needs a reviewer to write both, so it is low.
Recommendation: take the last line that matches `^Verdict: ` and require it to be exactly `Verdict: approve`. Take the first `^Prep reference: ` line and refuse a second one (lesson architecture/parsers-refuse-ambiguity). Add a spec case: a review with a quoted `Verdict: approve` line and a final `Verdict: changes` is not read.

### F6 [low] Some mechanical markers split a comment or give a reason that doesn't fit the line
Where: cc03d317, e.g. `pickman/tests/acceptance/c0015/workflow.spec.luau` near line 125, and `z-nile/tests/acceptance/c0001/tracker-lifecycle.spec.luau`.
Evidence:
- In c0015/workflow, the marker `-- c0120 override: pickman's files live in pickman/ (its home)` sits between "c0114 override: every" and "project root and the shared counter are tracker state". The `paths-ignore` line below it is marked "pickman's items live in pickman/.tracker (the fixtures' final layout)", which is a CI line, not a fixture.
- In c0001, a marker sits between two arguments of `must(…)`, and stylua then reflowed the call.
- f0061's matcher rewrite (two `par_start rojo build` matches replaced by a loop and two file checks) is marked only "the spec runs from its project's home after the move", which doesn't say the check now tests a loop.
JC1 is still met (every spot is marked). But group 3 is reviewed by its markers, and a generic reason makes the reader re-derive the change.
Recommendation: put each marker above the statement, never inside a sentence or an argument list. Where a hunk changes what a case asserts, not only a path, give the reason ("the gate now builds every project file in a loop; the case asserts the loop and both files"). `override-markers.luau` could also refuse a marker that falls between two comment lines.

### F7 [low] Once promoted, check-paths' live case is a standing rule for every future `check.sh`, and no skill states it
Where: `z-nile/.tracker/issues/c0120/acceptance/check-paths.spec.luau`, the case "every unfinished item's check.sh, in every project root, names only paths that exist from its home". The promotion dry run above runs it from `z-nile/tests/acceptance/c0120/`.
Evidence: after `done`, every later prep whose `check.sh` names a literal path is checked. If the path doesn't exist from its home and isn't under the item's or its raft members' Touched modules, z-nile's gate goes red on that prep's PR. An example is a path that a `depends_on` item, not yet done, will create. The testing skill's check.sh section (lines 106-108) and ticket-prep don't say so. The lesson testing/no-live-counts-in-promoted-specs asks of every promoted case that walks every unfinished item which later `done` or prep changes its set. Here the answer is every prep.
Recommendation: state the rule where `check.sh` files are written (testing skill, "`check.sh` files"): a literal path must exist from the home or lie under the item's or its raft's Touched modules. Name the exempt restamped files and say how they leave the list once re-prepped. If the design meant the case to be one-off at c0120's time, escalate to the user whether it should be promoted at all.

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"; groups 1-5 are untouched, `git log --first-parent` shows only new commits on top of 41d5fa15).
  - The overrides commits (cc03d317, 17acbd7d) touch only promoted specs and add only markers (plus stylua's reflow of 4 expressions the markers landed in, F6).
  - The hand-written commits (dd124f70, 7dd43cde, 1605944a, 2d748497, b4b0f83c, 95788496, bc244e72, 093f22d1, 61488eb7, 3b74b24d) touch only core paths, and every one is named in Touched modules: `z-nile/tests`, `z-nile/check.sh`, `pickman`, `z-nile/templates`, `.claude/skills`.
  - The merges carry only prep files (c0120's folder and its lessons).
  - No commit mixes a move with an edit. `override-markers.luau` confirms "every changed spot marked" (922/922).

## Lesson candidates (for the lead)
- review/sequestration-reference-not-a-ref, an addition: a sequestration check walks both trees. Every reference file must still be at HEAD (by item identity, across state moves), and every file at HEAD must match it. Check: does deleting or adding a sequestered file, or moving its item to `done/` by a merge, turn the check red, or at least make it judge that file?
- testing/guards-move-with-the-working-directory, an addition: the guard set has one owner. Every caller (runner, gate, `ac.sh`) gets the folders from one function. Check: grep every `pickman_fence_*` caller; does each fence the root and every registry home?

Verdict: changes
