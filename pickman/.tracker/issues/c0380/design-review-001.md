# Review 001: c0380 (design mode)
Inputs: prep commit 6ac3e828f (`prep-narrow-board-pins-for-revives`): `c0380.md`, `check.sh`, `acceptance/narrowed.spec.luau`, `experiments/prototype.patch` (sha256 d54ce0ed…1fa4, verified; 10 files, +191 −40), `experiments/mutants.py`, `experiments/mutants.txt`; `./zn capture c0380` (aa0c8fdbd). Read beside it: origin/main 24e6c4b30 (f0186 prepared there by #495, c311bfb36); c0156 (active, R0068) `consumers.luau`, `check.sh`, `prototype.patch` (sha256 ed053dfd…2f6c, verified); f0145's sequestered specs (blobs b242932f, d86ac1ea, c4157b4d, 383e4abf, as step 1 says); main's d0124/f0026 blobs (as step 1 says); `.worktree/prep-switch-to-arcade-paid-play` (c0202, 46f6f35f5); `proto-c0380` 084935271 and `proto-c0380-revives` 4302193d2 (the ten files' blobs are the same on both).
Run here: `./zn check c0380` (AC1 and AC2 red for the reasons the Wiring bullet gives); `./zn promote-check c0380` OK; `lune run z-nile/affected` on the six existing paths (each selects only itself); `git grep` of the ten paths and their item/basename spellings across every project; the narrowed spec, the nine narrowed files and c0128's golden, guards and titles specs on both prototype commits: 103 passed, 0 failed, on each.

The acceptance itself is tight: every one of the ten files is pinned by an exact-text digest, the cut keeps the mark, rank, name, score, level, order and count, and the C rows I re-read (C6, C8, C17, W1) die or survive where the table says. Scope matches the capture: the Problem and Solution are unchanged, the counts are detail ("eight"/"thirteen" are the capture's arithmetic; its lists give nine and fourteen), and "f0186 gains depends_on c0380" is already true on main. All four findings are about the work around this chore. None needs a change to the specs.

### F1 [medium] The Existing work section misses c0202's in-flight prep, which overrides two of the ten pinned files based on an emulation of this narrowing and never names c0380's narrowed.spec
Where: c0380.md, Checklist, **Existing work** ("No other branch or prep worktree changes the ten files (`./zn busy` and `git diff --name-only origin/main...HEAD` in every `.worktree/prep-*`, 2026-11-15 …)"); `acceptance/narrowed.spec.luau` PINS entries for `f0145/views.spec.luau` and `f0145/place.spec.luau`, and the case "every board text is compared up to the level, and nothing f0186 removes is pinned".
Evidence: c0202 ("Switch to arcade paid play") was claimed `preparing` on main at 21:16. Its prep commit, 46f6f35f5 in `.worktree/prep-switch-to-arcade-paid-play` at 21:52, is "design reviewed, before its review". `c0202.md:213-218` (Overrides) narrows `pickman/tests/acceptance/f0145/place.spec.luau`, dropping the two architecture assertions, and `f0145/views.spec.luau`, where every `Lobby.payLine` call gains a fourth argument, `Prices`. Its step 6 (`c0202.md:352`) also edits `done/f0145/check.sh`: AC1's line goes, and AC5 runs clients.spec alone. c0202 depends on f0186, which depends on c0380, so c0202 lands after this chore. Its E1 (`c0202.md:203`) and `experiments/overrides.patch` were cut on "c0380's narrowing of f0145's five cases emulated as c0380's captured Solution states it", not on this patch. Its views hunk carries the context `t.expect(string.find(buy, ", NEXT FREE GAME IN 42 MIN$") ~= nil).toBe(true) -- c0380` and `local line = Lobby.payLine({ … }, nil, NOW) or ""`. This patch has `).toBe(\`{buy}, NEXT FREE GAME IN 42 MIN\`)` instead, plus two new three-argument `Lobby.payLine` calls that build `buy`. `grep -n c0380 c0202.md` finds only lines 173, 203 and 352, so c0202's Overrides never names `pickman/tests/acceptance/c0380/narrowed.spec.luau`. When c0202 executes, three things follow:
- its views hunks do not apply;
- once applied by hand, the promoted narrowed.spec cases "tests/acceptance/f0145/views.spec.luau is exactly the narrowed file" and "…/place.spec.luau is exactly the narrowed file" go red, on a promoted spec c0202 did not name;
- c0380's two three-argument `buy` calls are left for c0202's executor to find.

The search the design names is a branch diff of the ten paths, which cannot see this: c0202's planned edits live in its document and in an experiments patch, not in its branch's diff.
Critique: a whole-file digest on ten files is a new rule for every item that will later edit any of them. The chore checklist asks which mid-prep items fail it on the day it lands, and what each does then. The tempting fix is one sentence, "c0202 will update the digests". That leaves c0202's prep, still before its own review, designed on text that will not exist.
Consequences:
- c0202 must re-cut its views and place overrides on this `experiments/prototype.patch`.
- Its Overrides must name c0380's narrowed.spec, with the two new digests computed by that spec's own rule (`exact`, then sha256, as its header says).
- It must keep, in `done/f0145/check.sh`, a `check "` line naming each of `/lives.spec.luau"`, `/top.spec.luau"`, `/views.spec.luau"` and `/place.spec.luau"`, because narrowed.spec's first case reads them.
- It must keep `upToLevel(` out of views and place (their `cuts` are 0).
- It must not put `livesText`, `LIVES_MARK`, "1 ROBUX A GAME" or `"lives spent"` back into any of the ten files.

c0198 ("Switch to arcade hiscores", draft, `depends_on: [f0197, f0145, f0186]`) deletes pickman's `Logic/Hiscores`, which d0124's, f0026's and f0145's specs require, so it inherits the same duty for whichever of the ten it changes. f0197 (prepared) cites lines of d0124/adapters and f0026/adapters in comments (`serve.spec`, `write.spec`: "from d0124/adapters :446" and others). The 17-line helper this patch adds near the top of both files shifts every one of those citations. They are provenance only and nothing reads them.
Recommendation:
- Rerun the existing-work search over every prep worktree's issue document (its Overrides line and Touched modules) and over every open item on origin/main, for the ten paths and their basenames, and record that search and its date in Existing work.
- Add c0202 to Existing work with the constraints listed under Consequences.
- Send them, with this patch's sha256, to c0202's prep lead now, and record the sending (date and channel), the way f0186's document records its note for c0198's prep.
- In Maintainability, add the same note for c0198's prep.
- Name f0197's line citations: tell its lead, or record that they stay as provenance.

c0380's own specs and check.sh need no change.
Lesson: z-design/new-rules-migrate-existing-work (also z-design/quote-other-preps-before-promising)

### F2 [low] Base b, E1/E2/E3 and the evidence for S3 name f0186's pre-review prototype, and the mutation runner does not notice that f0186 has since moved
Where: c0380.md, Unknowns & experiments, the `proto-c0380-revives` bullet ("df357513…6ac7, from `.worktree/prep-boards-show-revives` at 8f152dc86 … it is exactly the uncommitted working tree of `.worktree/proto-f0186-on-f0145`"); Solution bullet 3 (S3); `experiments/mutants.py` (no hash check).
Evidence: f0186 is prepared on main (#495, c311bfb36) with `experiments/prototype.patch` at sha256 f588be80…a791 (f0186.md E2: "refreshed after design review 001"). The two patches differ in one line: RevivesView's `gui.DisplayOrder = 0` becomes `1`. `.worktree/proto-f0186-on-f0145` now holds `DisplayOrder = 1`, so "it is exactly the uncommitted working tree" no longer holds. S3 ("With f0186's prototype changes from `.worktree/proto-f0186-on-f0145` applied …") was therefore proven on a tree that is no longer that one. The substance still holds:
- none of the ten files reads `DisplayOrder` or RevivesView;
- f0186's refresh changed none of its board text, `boards.spec` rows or Overrides;
- the 13 files still pass on 4302193d2, which is still built on df357513.

`mutants.py` checks no hash of the f0186, f0145 or c0156 patches its bases were cut from, and runs none of f0186's own specs on the unmutated base b. Its usage line (`python3 -I mutants.py <clone> <a|b>`) and the E2/E3 records also don't say they ran under `./zn run --time`, and a rerun would follow that usage line.
Critique: the design's own rule ("If f0186's review changes what it overrides … re-prep") is met, so nothing has to be re-cut. But the record that a re-prep or the final trace will cite for S3 points at a superseded patch, and the runner could not have caught it.
Consequences: none beyond the rerun. If the rerun turned anything red, that is the re-prep the Design already describes.
Recommendation:
- Rebuild base b on f588be80, run f0186's seven sequestered specs on it first, then the 13 files, E1 and the full gate. Record the hash and the results, and correct the "exactly the working tree" sentence.
- Make `mutants.py` refuse when f0186's patch on main (and f0145's two and c0156's) no longer hash to what its bases were cut from.
- Change its usage line to `./zn run --time <s> -- python3 -I mutants.py …`, and say E2/E3 ran that way, or rerun them so.
- In Acceptance criteria or the Test plan, say how S3 is carried: the files AC1 pins by digest are the files E2 ran green on f0186's prepared prototype, and f0186's own gate reruns them on its real code. That way the final trace has a test cell for `c0380:S3`.
Lesson: z-design/in-flight-bases-pin-their-source

### F3 [low] The c0156 guess doesn't say what the dependency costs: c0156 is R0068's last layer, so c0380, f0186, c0202 and c0198 all wait for the whole of R0068
Where: c0380.md, **Order** ("Guess (pending user, 2026-11-15): c0380 also waits for c0156 (… active in R0068)"); Checklist, Existing work ("it gains c0156 through c0380").
Evidence: R0068.md:37 orders the raft c0122, c0136, c0138, c0156. c0136 is the 695-line change to the harvest engine, the CLI and 14 skills (R0068 design-review-001). Only `origin/R0068/1/c0122` exists, and c0156 reaches `done/` only when R0068's `./zn done` runs. f0186's Order on main (f0186.md:173) still says c0380 is `depends_on: [f0145]` and "its raft starts after c0380 is in `done/`, which needs f0145 done first". The reason for the edge is sound: c0156's `consumers.luau` checks `D26 = "744eeb0f…"` and that f0026/adapters.spec still hashes to it, at c0156's `done`. But the user is asked to rule on the guess without knowing its cost or the alternatives.
Critique: the tempting fix is to add "R0068" to the sentence. The user still has nothing to choose between.
Consequences: each option has a cost:
- (a) Wait for R0068 whole: three more layers of tooling work before f0186 can start.
- (b) Take c0156 out of R0068 and land it alone first: a z-stop or unfold of an active raft, with R0068's grouped record and coherence review redone. c0156 shares only `zz-test/SKILL.md` text with c0122 and c0136, in three disjoint places (R0068.md:30).
- (c) Land c0380 first, then re-prep both c0156 (consumers.luau's D26, its prototype.patch's golden hunk, the kills/record anchors) and c0380. c0380's golden.spec base would then be main's 0187cfc4 under the old normaliser, so D26 and the golden PIN would be recomputed.
Recommendation:
- In Order, name the chain behind c0156 and put the three options, with their costs, into the guess for the user.
- Tell f0186's lead that f0186's `ready` now also waits for R0068 (its Order sentence is stale), and record the note.
Lesson: z-design/depends-on-inherits-the-dependency-raft

### F4 [low] c0128's golden.spec header still says D26 is the digest of R0045's narrowing applied to origin/main
Where: `experiments/prototype.patch`, the golden.spec hunk; golden.spec's header (lines 2-3: "its sha256 must equal the digest of the narrowing in R0045/experiments/narrowing.patch applied to origin/main"; lines 13-14: "a diff against narrowing.patch shows the rest").
Evidence: after this patch, D26 is the digest of R0045's narrowing plus c0380's. A diff of f0026/adapters.spec against `narrowing.patch` then shows c0380's four hunks, and nothing in the header explains them. The patch adds a two-line comment at `local D26` only. The Checklist's Restated rules says "c0128's golden.spec gains a comment on D26" and doesn't mention the header.
Critique: a reader who follows the header to diagnose a red D26 is sent to the wrong reference.
Consequences: golden.spec's PIN digest in narrowed.spec, the patch's sha256 (Design, first paragraph) and step 2's stat line change. Nothing else does.
Recommendation: add one clause to the header (for D26: R0045's narrowing with c0380's on top, `c0380/experiments/prototype.patch`), then recompute those three values.
Lesson: z-design/restated-rules-move-together

Lesson candidates: none new. F1 to F4 repeat existing lessons.

Verdict: changes
