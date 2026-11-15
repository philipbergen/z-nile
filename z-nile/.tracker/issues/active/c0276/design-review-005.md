# Review 005: c0276 (design mode)
Inputs: prep worktree `.worktree/prep-board-shows-lost-work` at 5d8fb89f with the working-tree c0276.md (sha256 7616d559e272…), check.sh (0302a72fa571…), acceptance/board.spec.luau (f7985edc3ba9…), acceptance/verdicts.spec.luau (61f46d66fe8a…), design-review-001..004, design-refute-001..004, harvest.md and the lessons it adds; prototype origin/proto-c0276 754e744d (both specs byte-identical to the prep's; its check.sh is still round 3's e128f9515cec…, without AC2's `land` label and AC4's transition grep; the prep's check.sh run on the prototype: AC4 PASS, AC1 to AC3's specs 6/0, 14/0 and 126/0, their FAIL lines the runner's sweeper exit 71); `git diff origin/proto-c0265-raft origin/proto-c0276 -- z-nile/engine z-nile/README.md z-nile/skills`; c0265's document at origin/prep-work-heartbeat 28e2c906 and the c0274, c0275 and c0277 hand-offs; c0121's sequestered specs on main (its `overrides.patch` touches only c0118/docs; none pins the card or band-head strings); `./zn capture c0276` (8577a496, a confirmed capture: title, Problem and Non-goals unchanged, the Solution only gained detail). Since the prototype's base 1758cf21, main changed nothing under `z-nile/engine` and, of the files the specs load, only `tests/lib/fakecli.luau` (the fake model CLI's modes, which board.spec never runs). All runs were in scratch clones of 754e744d with origin removed, under /private/tmp/claude-501/-Users-philipbergen-code-pickman/3fbf9326-e053-49c8-ab1e-bfbc221fe8f4/scratchpad/r5 (`proto`, `proto2`, `proto3`; mutants in `scripts/muts.json`, applied one at a time by `scripts/mut.py` through `./zn run`; probe copies of board.spec at `proto2/z-nile/.tracker/issues/c0276/acceptance/probe.spec.luau` and `proto3/…/probe.spec.luau`). Nothing in the repository was edited. Baseline on the bare prototype: verdicts.spec and board.spec 20 passed, 0 failed.
Dropped from review-004: F1 (L1 re-run: board 13p/1f at :349), F2 (Nn3 re-run: 8p/6f at :257, :273, :299), F3 (the transition is in §5, Usability and the zz-rules row; AC4 passes), F4 (W1 re-run: 13p/1f at :255), F5 (step 6 stops an executor who finds no recorded answer).
Regression runs on the prototype: every reader of the docs and board files (`grep -rlF -e "zz-rules/SKILL.md" -e "z-nile/README.md" -e "README.md" -e "engine/board.luau" -e "engine/board.html" -e "board.html" tests/acceptance tests/tooling --include='*.spec.luau'`, 37 files) with c0118, c0073 and `tooling/board`: 380 passed, 0 failed, 49 files (the zz-rules row changed after round 003's docs run); fourteen publishing specs (c0053/*, c0068/stop, c0081/allocate and publish-guard, c0116/claims and recombine, c0072/*, c0005/*): 146 passed, 0 failed. `Overrides: none` holds. Q1 (the served board and the c0257 app), the band-head decision, the per-publish latency and the choice of engine for the transition are the user's and are handled as stated.

### F1 [high] Two of AC2's failure cases read the page an earlier case wrote: a `./zn board` that warns once, exits 0 and builds nothing when origin is unreachable passes check.sh
Where: board.spec, the cases "an unreachable origin builds the board…" (lines 291-301) and "a document another checkout moved…" (303-313); Design §3 ("The page is built in every case and the command exits 0"); AC2 ("each build the page"); the capture's third outcome ("The board still builds when the heartbeats or pull requests cannot be read").
Evidence:
- Every `./zn board` failure case writes the same `--out .cache/board-c0276.html`, and none removes it first.
  - In run order, the case before the unreachable origin is the unreadable-heartbeats case. It leaves a page with one note and no marks, which is exactly what the unreachable-origin case asserts: `#notesOf == 1` and c0010 unmarked. The note's text is not checked.
  - The vanished-document case comes next and asserts the same two things, plus `fs.isFile(page)`, which the earlier file satisfies.
- Mutants, each applied alone:
  - V1: the unreachable-origin branch says its warning, then `process.exit(0)`, so no page is written. board.spec: 14 passed, 0 failed.
  - V2: the same in the throw branch. 14 passed, 0 failed.
  - Control V3: the same in the registry branch. 13 passed, 1 failed at :393. It dies only because the case before it (`PICKMAN_PUBLISH=0`) happened to leave a page with no note; reorder the cases and it survives.
  - V2b: `boardVerdicts` without its own `pcall`, while `cmd.board` wraps its call in one and writes the page unmarked under the design's warning (the shape `buildBoard` already has). board.spec: 14 passed, 0 failed. In a rebuild, the throw then reaches `buildBoard`'s old `pcall`, which prints "could not rebuild" and writes no page. The main board keeps the state from before the publish, and no case throws inside a rebuild.
- Offline is the usual way the heartbeats can't be read. The fetch of main is the first read, so it is the first to fail. "When origin can't be read, keep the last page rather than replace it with one that shows nothing lost" is a natural choice for an implementer, and it is V1.
Critique: Round 001 F3 found that AC2 passed an offline `./zn board` that failed outright. The cases added for it can't tell a page built now from one built earlier, so the same outcome now passes a different wrong implementation. The mechanism at fault is the output path all the cases share, not any single case. The tempting fix is to delete the file in the two cases named here. That leaves V3's kill resting on case order, and leaves the throw unpinned where the rebuild acts.
Consequences:
- Removing a page that the previous case (under a mutant) never wrote must not throw: Lune's `fs.removeFile` errors on a missing file. Guard the removal, or give each case its own `--out` path.
- A sync case under `noshow` must hold under the later layers. The main checkout holds no beat entries (c0275), and the only `git show origin/main:<issue>` that `sync` makes is `claimsOf`'s (from reading `cmd.sync` and `sweepStale`).
Recommendation:
- In every `./zn board` failure case (pull requests, heartbeats, origin, vanished document, malformed branch, `PICKMAN_PUBLISH=0`, registry):
  - write to a path no other case uses, or remove the page first (`if fs.isFile(p) then fs.removeFile(p) end`);
  - assert the note's own text: `origin/main could not be read`, `could not be read; built without them`, `projects could not be read`.

  On a probe copy of board.spec with that change in the origin and vanished-document cases: the prototype 15 passed, 0 failed; V1 14p/1f (the unreachable-origin case); V2 14p/1f (at :313).
- Pin the throw where the rebuild acts: a case that pushes `another terminal's issue`, removes the main checkout's page, then runs `./zn sync` there under `noshow`. Expect exit 0, the page rebuilt (the new issue on it) and one note. On a probe: the prototype 16 passed, 0 failed; V2b 15p/1f (the new case).
- Add Rules rows, all `run`:
  - "an unreachable origin still writes the page" (V1);
  - "a throw still writes the page" (V2);
  - "a throw inside a rebuild still writes the page" (V2b).
Lesson: zz-test/no-vacuous-pass, zz-test/pin-fail-safes-where-they-act

### F2 [medium] "A rebuild does not fetch main a second time" is pinned for the sync alone and for one spelling: publish and land rebuilds that fetch main again pass
Where: AC2 ("a rebuild does not fetch main a second time"); Rules row "a rebuild trusts its caller's fetch of main" (Mh); board.spec "a rebuild after a sync does not fetch origin main a second time" (352-367); Design §3 (`fresh`).
Evidence:
- The case counts only fetchlog lines containing `origin main`, and only around one `sync`.
- V4: `buildBoard(root, fresh)`, with `refreshBoard` passing false, so every publish and land rebuild fetches main again while sync still passes true. board.spec: 14 passed, 0 failed.
- V10: the rebuild fetches `origin refs/heads/main`. 14 passed, 0 failed.
- The cost is the double read that review 001 F4 measured before `fresh` existed: +15% to +40% on three publishing specs. It lands on every publish in every fixture, and adds a second network read to every publish on the real repository.
Critique: The rule exists for the publish path, which every fixture spec takes, yet the case pins the caller that matters least.
Consequences: A publish case would break under the later layers: a beat fetches main (`beatPaths`), and c0275's first beat follows a claim's publish. So count where no later layer beats: `land` from a capture worktree (no entries, so no tick) and `sync` in the main checkout.
Recommendation:
- In the shim, log pushes as well as fetches.
- In the land case, count the fetches whose arguments name `main` after the push to `refs/heads/main`: exactly one (land's own).
- In the sync case, count every fetch that names `main`, not only `origin main`.

On a probe: the prototype 15 passed, 0 failed. V4 fails the land case (expected 1, got 2). V10 fails both the land and the sync case.
- Add the Rules row "publish and land rebuilds trust their caller's fetch", with V4 and V10.
Lesson: z-design/spec-design-correspondence

### F3 [low] The no-origin half of "a checkout with nothing to publish to reads no remote and prints nothing" has no case
Where: §3 (`publishing()` false: "no origin, or `PICKMAN_PUBLISH=0`"); AC2; Rules row N18.
Evidence:
- V5 replaces `not publishing()` with `process.env.PICKMAN_PUBLISH == "0"`: board.spec 14 passed, 0 failed.
- Without an origin, the board then tries the fetch, prints `warning: board: origin/main could not be read; …` and puts a note on the page (reasoned from the first read in `boardVerdicts`).
- Review 002 F3 offered this case as optional, and refute 002 didn't add it.
Critique: Small: the result is a stray warning, not a remote read. But AC2's text claims the rule.
Consequences: The case needs a clone without a remote inside the fixture's `.cache`, and must leave the shared fixture's config alone.
Recommendation: Do one of these:
- add the case: `git clone` the fixture's main into `.cache`, `git remote remove origin`, run `./zn board` there, and expect exit 0, empty stderr and no notes;
- or narrow AC2's words to `PICKMAN_PUBLISH=0` and mark the no-origin row `reasoned`.

### F4 [low] The note is drawn only on the Board view
Where: §2 ("drawn in the page's `#problems` area"); board.html line 123 (`#problems` sits inside `<section id="board" hidden>`); Usability.
Evidence: `renderList` draws the Rafts and Issues views, with their marks, while `#board` is hidden, and the note lives in `#board`. A person on the Rafts view, where a raft's own claim is marked, sees an unmarked list and no reason why.
Critique: The page opens on Board, so most readers see the note. Still, the promise of "one note on the page" holds on one view only.
Consequences: none.
Recommendation: Draw the notes where every view shows them (above the list as well), or say in §2 and Usability that the note shows on the Board view.

### F5 [low] Sentences left stale by round 004's answers
Where: §1; §4's c0118 row; AC4 (document and check.sh label); Usability; AC2.
Evidence:
- §1 says "`board.build` keeps `(root, checkout, facts)` and gains the trailing optional `verdicts`". It gains `verdicts` and `notes`, as the signature a few lines above shows. §4's c0118 row says "c0276 adds a fourth after it"; it adds a fourth and a fifth.
- AC4 says the README's board paragraph names "the protected-checkout rule and the transition". The prototype's README paragraph has no transition sentence, and AC4's README greps check neither the transition nor "unprotected checkout". The transition is stated in the zz-rules row (refute 004 F3).
- Usability says "a read that failed says why in one `warning: board:` line". It now says it in one line and one note on the page.
- AC2 names `land` twice: "every publish and `land` rebuild" and "the board a `land` rebuilds carries the verdicts too".
Critique: An executor reads §1's sentence, and AC4 promises a README sentence that nobody writes.
Consequences: none.
Recommendation:
- Fix the sentences above.
- For the README, either add the transition sentence and its grep, or say in AC4 that the transition is stated in the zz-rules row only.
- Bring the prototype's check.sh up to the prep's.

Lessons added (harvest.md): the four z-design lessons and the note on zz-test/seed-every-enumerated-case are each a lesson another raft could fail, not restated findings. `./zn lessons --check`: 269 lessons, ok. `./zn lessons --uncovered c0276`: every finding is covered.

Candidate note for the lead on zz-test/no-vacuous-pass (from F1): a case that asserts a command wrote a file starts with that file absent, or uses a path no other case writes, and asserts content only this run could produce. A page left by the previous case passes a case whose command wrote nothing. Check: if this command wrote nothing, would the file this case reads still satisfy it?

Verdict: changes
