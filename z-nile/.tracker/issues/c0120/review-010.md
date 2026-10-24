# Review 010: c0120 (code mode; the coordinator's round 007 of #107)
Inputs: `origin/impl2-c0120` at b99ba63c (PR #107). The fix delta is `git log --first-parent 7a01bd47..b99ba63c`: the merges 8fccc88f, 95cc2a4e, 2a78e835, d95c13ad and b99ba63c, and the commits 529c2f6b, 482c20c7, a69ec26b, b21d07fb, c68aa55d and 6f2dd3bd. The prep merged in is `origin/prep-c0120` 6f6adf61..56fc62dc: de83ffff, 72fd1238, the main merge 6dccba40, 8683244c, 30500b87 and 56fc62dc. `git diff origin/prep-c0120 HEAD -- z-nile/.tracker/issues/c0120` is empty. I read review-009, refute-009, c0120.md (Guesses 18 and 19, step 12, Rules rows V29 to V31, JC1), `./zn lessons --when build --full` and the review lessons first. Every run was in scratch clones under `code-review-c0120b-007/`, each with a bare mirror of GitHub as its `origin`. Nothing was fetched into, run in or written to the real repository. The real remote was only read, with `git ls-remote` and one mirror clone.
Dropped from review-009: F1 to F5, each fixed as refute-009 says (checks below). F1's fix is the user's "Reviewed overrides patch" (Guess 19).
The user's decisions applied: "Reviewer-pinned commit", "Reviewed by commit group" (earlier groups untouched; the new commits are judged as one group) and "Reviewed overrides patch".

## What was run
- **Gates**, each in its own clone at b99ba63c:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1404/206, z-nile 959/143.
  - `pickman/check.sh --full`: GATE PASSED. 1404/206.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 959/143.
- **c0120's `check.sh`** (`./zn sync --fetch`, then `./zn check c0120`): 15/18. Each red is an allowed one, red for its stated reason:
  - AC11: only `pickman/.tracker/rafts/R0044/check.sh: tracker/issues/done/c0128 (from pickman)`. R0044 was prepared on main in the old layout. c0114's two lines from round 009 are gone, now that c0114 is done;
  - AC16: only other agents' branches (`origin/impl-c0120`, `prep-c0115` to `prep-c0118`, `prep-skill-lessons`);
  - AC18: `no approved review … records a "Prep reference: <sha>"`.
- **AC18 with a stub approving review** that pins 56fc62dc (not committed): **green, 251**, `main 9734bb65… from <the mirror>`. override-markers from the renames commit: all 1104 hunks marked.
- **Promotion dry run.** `git mv` of c0120's `acceptance/` to `z-nile/tests/acceptance/c0120`, then `z-nile/check.sh --full`: pickman 1404/206; z-nile 1063/157 with 1 failure, check-paths' live case. That is AC11's R0044 line, the expected red.
- **The supersede rule** (56fc62dc: `landed`). Clone `atk2`, with the stub review. Each plant was committed on b99ba63c, then reset:
  - `z-nile/tests/acceptance/c0114/finished.spec.luau` (main changed it after the stack's text landed) gets a marked `if true then return end`: **red**, `changed`;
  - c0114's finished `check.sh` loses `z-nile/next` from its AC13 pathspec: **red**, `not its text with exactly the rewrite`;
  - c0131's `accept.spec` hook pointed at `/usr/bin/true`: **red**, `changed`.

  `landed` only turns a refusal into "main's published text (with the pinned patch)", so the author can't widen the reference through it at today's `pre`. F1 below moves `pre` itself. F2 covers what the rule leaves out.
- **The regenerated patches.** For every spec main promoted under `tests/acceptance/{c0114,c0127,c0131}`, I diffed main's text at 9734bb65 against HEAD's at `z-nile/…`:
  - The changed lines of that diff are exactly the `+`/`-` lines of `c0114-overrides.patch` plus `main-overrides.patch` (604 each; one blank line sits in a different place in diff's alignment).
  - `c0114-overrides.patch`'s change lines are identical to the version reviewed at 6f6adf61. Only the index line, the hunk offsets and the context (main's added `fixture` and `trackerfix` requires) moved, so `--3way` hid nothing.
  - Main's own change to c0114's specs (finished.spec's new "reads main's tip from origin" case and finished.luau) runs unoverridden and passes in the gate.
  - `main-overrides.patch`, read in full: every hunk is layout only. It moves the fixtures to the home's `.cache`, gives the runner copy the homes layout (`z-nile/tests/run.luau` and `tests/lib`, `z-nile/.luaurc`, `cwd = {repo}/z-nile`, the lock and signals under `z-nile/.cache`) and moves the probe paths. No assertion changed.
- **`tracker/next`** (b21d07fb): right. `ids.OLD_FILE` is root-relative (`tracker/next`). The tombstone belongs at the root, where an engine from before the move reads it. A copy at `pickman/.tracker/next` would sit in a project root that nothing reads. 7a01bd47 still had the old parsing counter at `tracker/next`, which would have counted beside `z-nile/next`. HEAD has main's exact tombstone and `z-nile/next` (main's), and `./zn audit` is clean.
- **The ported tooling specs** (a69ec26b, 6f2dd3bd), diffed against main's texts:
  - `lock-start-ids`: the same layout changes as c0127's override and nothing else. All four cases keep their assertions. The lock path is the one the runner takes (`fence.luau`: `{cache}/tests-run.lock`, the home's `.cache`), and `heldBy` fails if it isn't;
  - `audit-raft-roots` and `window-new-raft`: the registry is read at the top, and pickman's root is spelled `pickman/.tracker`, in the fixtures and in the expected messages. The cases, their order and their assertions are unchanged;
  - repo-fence: main's keys moved to the promoted place `z-nile/tests/acceptance/<id>`, and the two item-folder keys (no longer needed, since both items are done) dropped. That is narrower, which is right.
- **The merge of R0043.** Every core file main changed that HEAD doesn't carry verbatim (`z-nile/engine/*`, `z-nile/lib/*`, `tests/lib/*`: 15 files) was checked with `git merge-file`, using base = the stack's c0114 tip (26b5ddce^2), ours = 7a01bd47 and theirs = 9734bb65:
  - 14 equal HEAD exactly;
  - `main.luau` had 2 conflicts, both resolved to main's text. The mechanical merge would have kept a duplicate `refuseInWindow("new raft")`, and HEAD keeps only main's call, after `refuseStale`;
  - `fence.luau`'s change since 7a01bd47 is main's change line for line, except where c0120's own reviewed moves were already applied;
  - `reference-transaction` is main's (c0131's) at `z-nile/lib/git-hooks/`.
- **Fence spot-check (item 8).** Clone g1, macOS as shipped. Round 009's probe item c9998 (rev-parse, update-ref, add and commit in `.cache` and `.cache/atk` of the root, `pickman/` and `z-nile/`, plus an update-ref from its home) was run from the root, `pickman/` and `z-nile/`, with no environment and with an absolute `GIT_DIR`: **6 runs, 0 open**. The fingerprint (refs, local config, HEAD, `ls-files -s`, worktrees, hooks, stash) was identical before and after, with no `pwn` refs. The delta changes no fence file beyond main's own changes.
- **Whole-main merge simulation** (clone `msim`). The current origin/main, read with `git ls-remote` from GitHub, is **d3d8f137**: 4 commits past 3331623f (c0138 captured, R0044 preparing).
  - `git merge origin/main`: clean. Git followed d0124 and R0044 to `pickman/.tracker`. c0138 lands in `z-nile/.tracker` (a tooling capture, so no move), and `z-nile/next` is main's.
  - AC18 with the stub: **green, 252** (`main d3d8f137…`). override-markers: all 1104 marked. `./zn audit`: 0 errors, 0 warnings.
  - `./zn check c0120`: 15/18, the same three reds (AC11 only R0044).
  - The gate on the merged tree: pickman 1404/206, z-nile 959/143: **GATE PASSED**. (My first run refused, because I had set a fixture identity in that clone's config. The runner's tripwire was right, and I removed the identity from my scratch clone.)
- **Sequestration (item 2).** The new group changes no sequestered file outside c0120's own folder, except through step 12:
  - the finished rewrite (482c20c7, AC18-checked);
  - the overrides from the two pinned patches (c68aa55d, AC18-checked).

### F1 [high] AC18's two anchors come from commits the author makes: restoring and re-deleting `tracker/rafts/done/R0001/check.sh` re-anchors "before the move" to any tree, and group 4 is pinned only by a subject the author types, so a weakened `check.sh` is green
Where: `rewrites.premove`: `git log -1 --format=%H -- <MARK>`, then its parent. `finished.luau`: `coreRev` is the third first-parent commit after that one, accepted when its subject starts with `c0120: run each project from its home` (code review 009 F2's fix). c0120.md line 282 ("the parent of the commit that removed `tracker/rafts/done/R0001/check.sh` … found whether the PR is squashed or not").
Evidence: clone `atk`, from b99ba63c, with the stub review uncommitted:
- **Control.** A commit sets c0128's AC4 to `check "AC4: …" true`: AC18 **red**, `pickman/.tracker/issues/c0128/check.sh: changed`.
- **The attack**, on top of that commit:
  - commit "tidy" restores MARK from aed3e6f1. It also sets the four Guess 17 files to their pre-move text and removes `z-nile/next`, so the rewrite of the re-anchored base reproduces HEAD;
  - commit "tidy 2" removes MARK and puts the four files and `z-nile/next` back;
  - then two empty commits, and an empty commit with the subject `c0120: run each project from its home (again)`.
- The net diff against b99ba63c is the c0128 line alone (`git diff --stat`: 1 file, 1 line).
- AC18: **green**, `finished: 203 sequestered files are their reference (before the move 9ccb0daa…, main 9734bb65…)`.
- `pre` is now the author's "tidy" commit. B = merge-base(pre, M) = M, so no file counts as changed on main, every reference is the author's own text, and the weakened AC4 is its own reference. The `landed` rule isn't even needed.
- The only tells are a different `before the move` sha and a judged count of 203 instead of 251, which nothing compares.
Critique: this is the third derived input in this mechanism that a commit can choose: the world in review-009 F2, and now the base and the core. Round 009's lesson candidate said it: "anything a reference is computed from … is a reference too". The subject pin from that fix answers the per-file choice, but a subject is text the author writes. The tempting fix is to refuse a second commit that touches MARK. Main still carries MARK and can change it, and history simplification decides which of main's commits `log -- MARK` sees, so that patches one spelling of the attack and leaves the search.
Consequences:
- A pinned sha must survive what AC18 meets before landing: merges of main (fine, the first-parent line is never rewritten, per the user's groups).
- It must not break what runs after landing. The promoted `finished.spec` resolve case and check-paths call `premove` on the real tree, where a squash gives the move a new sha. So the pin is AC18's (and override-markers') alone, and `premove`'s search stays for the specs that run after landing.
- finished.spec's fixtures build their own histories, so they must be able to record their own anchors the same way.
Recommendation: AC18 takes both anchors from the reviewed record, never from a search. Do it in the same way as `Prep reference` (only a reviewer writes it, and approving it pins it): the reviewer-pinned prep holds the move sha and the core sha (for example a `anchors.txt` beside c0120.md, read from `ownBase`), or the approving review records them. AC18 refuses unless:
- `premove` from HEAD gives exactly the recorded move;
- the move and the core are both on HEAD's first-parent line;
- the core is the third first-parent commit after the move.

The subject check can stay as a second guard.

Cases for finished.spec:
- the attack above in the fixture (MARK restored and removed later, a forged core subject) → refused, naming the recorded move;
- the recorded anchors with an ordinary main merge on top → green;
- mutants: `premove`'s result used unchecked (killed by the first case); `coreRev` by subject only (killed by a forged-subject case).

Add a Rules row for each. Guess 18's paragraph names the anchors as reviewer-pinned inputs.
Lesson: review/sequestration-reference-not-a-ref (its "inputs a reference is derived from are references too", here the base and the core).

### F2 [medium] The supersede rule is in no design text, and it is wider than it claims: `--find-object` searches every commit of main's history at any path, so a stack text that equals any blob main ever had counts as "landed"
Where: `finished.luau` (56fc62dc), `git log -1 --format=%H --find-object=<pre's blob> M`. c0120.md Guess 18 still says "a file that main and the branch's base (c0114's build) both changed, differently, refuses". No Rules row records the rule or a mutant run.
Evidence:
- For c0114's `finished.spec.luau` the rule fires through 61ae82db, R0043's prep on main (the blob 78b75609 was added to main there), which is the case it was written for.
- The search has no range and no path. A blob main had before B (the stack reverting a file to an older main text) and an identical blob at another path both make `landed` true. An identical blob elsewhere needs only two files with the same bytes, which the rule's text never rules out.
- In either case main's text silently replaces the stack's change, where the rule as designed refuses.
- Today `pre` is c0114's final tree, and c0114 has landed, so no wrong verdict follows. The verdict stops being fixed once `pre` moves (F1), and the next stacked raft inherits the rule.

The fixture case (f0074) and the old f0073 refusal kill "landed always true", but nothing kills "landed for any blob anywhere".
Critique: the tempting fix is to document the rule as it is. That records a rule that answers yes in cases nobody decided.
Consequences: the restriction must still see c0114's case. There the stack's path (`z-nile/.tracker/issues/c0114/acceptance/finished.spec.luau`) and main's (`tests/acceptance/c0114/finished.spec.luau`) differ, and the blob arrived through main's prep between B and M.
Recommendation:
- Restrict the search to `B..M` and to the key's own paths on either side: `git log --format=%H --find-object=<blob> B..M -- <p.path> <m.path>` (and any path main's history gives that key, if a move sits between).
- Write the rule into Guess 18 ("main's text supersedes the stack's when the stack's text reached main between B and M at that item's place"), with a Rules row.
- Cases:
  - the stack's text equal to a main blob from before B, main changing it after → refused;
  - the stack's text equal to a blob at another item's path → refused;
  - the f0074 case → still green.
- Mutant: the range or the pathspec dropped.

### F3 [low] The finished rewrite never rewrites a root path that main created after the move's base: c0114's AC13 now names `z-nile/next` from `z-nile/` (that is, `z-nile/z-nile/next`), and AC11's finished half calls it "stale before the move"
Where: `rewrites.rewrite` rewrites a literal only when `world.before(path)` holds. `finished.spec` "every finished check.sh … resolves" skips a literal when `world.before` is false. `z-nile/next` exists only on main since its first publish after R0043 landed, so it is in neither the pre-move tree nor the rewrite's view.
Evidence: HEAD's `z-nile/.tracker/issues/done/c0114/check.sh`:
`check "AC13: this branch changes neither tracker/next nor z-nile/next" git diff --quiet origin/main...HEAD -- ../tracker/next z-nile/next`. The check runs from `z-nile/`, so the second pathspec names a file that cannot exist, and that half of the criterion is vacuous. A probe over every finished `check.sh` (literals missing from the home and absent before the move) finds this as the only one that exists at the root now. The rest were stale before the move.
Critique: c0114 is done, so the line is history today. Step 12 runs after every merge, though, and each tooling item main finishes in the window can name a root path main added since B. Only paths that stay at the root (not moved by §1) are affected.
Recommendation: let the rewrite's `before` also hold main's tree at M (a path main has at the root counts as one the move must rewrite), in prep, so AC18's expectation and `rewrite-finished` agree. Case: a finished `check.sh` naming a root file main added after B, run from `z-nile/` → rewritten to its home-relative path. Mutant: `before` from the pre-move tree only.
Lesson: testing/no-vacuous-pass.

### F4 [low] `main-overrides.patch`'s two marker texts are swapped in three places: "its fixtures go in its home's .cache" sits above `local home = …`, and "its runner copy has the homes layout" above `local base = \`{home}/.cache/…\``
Where: `main-overrides.patch`, c0127's `reuse.spec` (first hunk), c0131's `accept.spec` and `refuse.spec`.
Recommendation: swap the two texts in prep when the patch is next regenerated. override-markers counts markers, not their words, so nothing else changes.

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"). `git log --first-parent 7a01bd47..b99ba63c` holds only the commits listed under Inputs, and groups 1-5 are untouched. Each commit is one kind:
  - 529c2f6b: a document line;
  - 482c20c7: `rewrite-finished`'s output alone (8 files, 20 lines; AC18 accepts it);
  - a69ec26b and 6f2dd3bd: tooling specs;
  - b21d07fb: the counter's placement;
  - c68aa55d: overrides alone, exactly the two pinned patches;
  - the merges: prep and main.

  No commit mixes a move with an edit. F1 is a hole in AC18, not in the group: the group itself holds no anchor-moving commit.

## Prep reference
Not recorded: F1 and F2 are defects in AC18 itself. Prep 56fc62dc's changes in c0120's folder since 6f6adf61 are the ones this round reviewed:
- de83ffff (Guess 19, V29 to V31, and the review-009 fixes in `finished.luau`, `finished.spec.luau` and `rewrites.luau`);
- 72fd1238 and 8683244c (the two patches, checked above);
- 30500b87 (refute-009);
- 56fc62dc (the supersede rule and its case).

Nothing else changed in the folder; 6dccba40 changed it only through those. With a stub approving review that pins 56fc62dc, AC18 was green at b99ba63c (251) and on the tree merged with today's main d3d8f137 (252).

## Lesson candidates (for the lead)
- review/sequestration-reference-not-a-ref, an addition: an anchor a check finds by searching history (the commit that removed a file, the Nth commit after it, a subject) is chosen by whoever commits next. Pin anchors by sha in the reviewed record. Check: can a commit added now change which commit this check calls "before" or "the core"?
- testing, new: a "seen before" test by blob (`--find-object`) is a test of content anywhere, ever. Check: is the search bounded to the range and the paths the rule names?

Verdict: changes
