# Review 001: c0392 (design mode)
Inputs: `prep-narrow-c0210-lobby-pin` at 22f96913a: `c0392.md`, `check.sh`, `acceptance/narrow.py`, `experiments/` (both patches' sha256 match the document: fb324c36…8d31 and ae809463…a2ac2), `mutants.out`, `idea-review-001.md` and `idea-refute-001.md`. Also: `./zn capture c0392` (4259b03c8) and main's history of the document (dd85d4495, PR #526). c0210's prepared folder as on origin/main 5ca319f4e: `check.sh` is blob 0fefecb3, `lobby-start.spec.luau` is blob 2efc8d8a, and the 27 `KEEP` blobs all match. `c0210-check.patch` applied to a scratch copy gives 259b5159. f0209's document in `.worktree/prep-portal-start-place` (75664306e and its uncommitted edits, read only). Prototype A's `portal/experience.json` and `portal/scripts/lib/beta.luau`. `z-nile/engine/trace.luau`, `approval.luau` and `main.luau`'s approval call sites. z-ready step 2. `lune run z-nile/affected` on the touched paths (nothing selected). `grep -rlF` of `lobby-start` and `c0210` over every `tests/acceptance` (only c0053's unrelated fixture id).

### F1 [high] The Problem, Non-goals and Solution are PR #526's rewrite, not the capture, so a captured outcome is now a Non-goal with no Scope decision
Where: c0392.md:18-30 (Problem, Non-goals, Solution); c0392.md:65 (the Guess's option (b), "This is a scope change"); `## Open to the human` (none).
Evidence: `./zn capture c0392` prints `capture 4259b03c8 … tracker: new c0392 Narrow c0210 lobby start-place pin (#521)`. Its Solution says "Remove from `portal/tests/acceptance/c0210/lobby.spec.luau` only the pins the Problem lists, so the file passes on main both before and after f0209", and "Every other assertion in the file stays as it is, including the Pickman game case's checks (… the publish order …), the `*PlaceId` attributes on the start place and the runtime case's `--place Pickman` half". Its Non-goal says "c0210's other specs and its `check.sh` are not changed".

The document's text instead comes from dd85d4495, "tracker: c0392 recaptured for c0210's split lobby spec (#526)". f0209's prep lead wrote it (f0209.md:141, "recaptured PR #526") after c0210's prep split `lobby.spec`, and the idea stage was rerun. That subject is not a capture: zz-rules' capture row counts only `tracker: new`, and z-ready step 2 lands a scope change as `tracker: scope <id> …`. The document has no `Scope decision (user, …)` or `Decided with the user` line.

After the split, two of the captured kept assertions that still hold after f0209 exist only in `lobby-start.spec.luau`:
- `seen[2].path` is `/universes/v1/111/places/222/versions`: the start place is published second, to its own id. `pickman.spec` checks only `seen[1]`.
- `PortalPlaceId` 222 and `PickmanPlaceId` 333 on the start place.

The rewrite deletes them with the file and moves them into the second Non-goal ("No replacement is added for the removed file's end-to-end pin with the real manifest …"). It also adds the `check.sh` change the captured Non-goal ruled out.

The consequences are concrete:
- z-ready step 2 compares each member's Problem and Solution with `./zn capture`, and on a mismatch it stops and asks the user.
- `./zn trace` derives `c0392:P1` and `S1` to `S3` from the captured text (`trace.luau:391`). The final review would then need a design and a test for "the `*PlaceId` attributes on the start place … stay", which this design deletes.
- The Guess's options call keeping a narrowed case "a scope change", which is backwards when measured against the capture.
Critique: the idea challenge's `revise` was a reviewer's recommendation, not the user's decision (the c0330 note in the lesson below). The tempting fix is to write a `Scope decision` line or a Guess in the author's words. That records no user decision.
Consequences: either answer changes the design materially. Keeping the capture removes the pre-ready PR and keeps AC11, whose label then goes stale; AC1 pins a narrowed file instead of an absence, and f0209's Overrides row changes. Confirming the rewrite needs the ruling in the two places that read it: z-ready's scope check and the final trace.
Recommendation: escalate to the user:
- **(a) Confirm #526's scope.** Their words go in the Problem as `Scope decision (user, YYYY-MM-DD): "…"`, landed by a `tracker: scope c0392 …` PR or in this prep PR (z-ready step 2). The same ruling goes under `## Open to the human` as a `Ruled (user, …)` bullet, so the final trace can mark the captured S2 `not met: "<ruling>"`. That stays true until open PR #348, which reads trace claims from the approved ticket, lands. Cost: nothing to build. Until f0209's `deploy.spec` and `start.spec` land, no spec checks with the real manifest that the start place is published second to its own id and carries the ids.
- **(b) Keep the captured scope.** The raft narrows `lobby-start.spec.luau` in place.
  - Both deploy cases keep `r.ok`, `#seen == 2`, `seen[1]` to 333, `seen[2]` to `/places/222/versions`, `PortalPlaceId` 222 and `PickmanPlaceId` 333 on the start place, and the `version=1333` line.
  - They drop the `Lobby` child and the no-`Server` check, `GamePlaceId`, `LobbyPlaceId` nil, the exact output with `lobby_version` and the lobby project check. The `--place Portal` case goes too.
  - c0210's `check.sh` stays blob 0fefecb3: AC11 runs the narrowed file, so no pre-ready PR is needed. Its label goes stale, and the user says whether a tracker PR relabels it.
  - AC1 pins the narrowed file's reviewed golden, with one N row per kept assertion. E2's L1 (the `portal` build) run against the narrowed file turns the Solution's "both builds" into a Checked result.
  - The narrowed file names no build, so it holds after f0209 and through c0188, unlike the Guess's option (b).
  - f0209's prep, which is answering its own review now, changes its Overrides row and its AC6 note from "removed" to "narrowed". c0392 records that c0210's Interfaces sentence ("f0209's chore removes that file") is superseded.
  - Cost: a rewritten spec, a golden and mutants instead of a deletion.
Lesson: z-design/never-narrow-captured-scope

### F2 [medium] Nothing enforces the window order the design chooses: with `depends_on: [c0210]`, `ready` and z-work take c0392 as soon as c0210 is done
Where: c0392.md:7 (`depends_on`). c0392.md:65, the Guess: "c0392's raft is readied only once every other `depends_on` of f0209 (c0210, f0206, f0208, c0202) is done … z-raft writes this into c0392's raft's Order & dependencies". c0392.md:159-162 (step 0).
Evidence:
- `./zn ready` checks only that every `depends_on` outside the raft is in `done/` (z-ready step 2; zz-rules, `ready`). z-work keeps taking "the next one ready would accept".
- c0210 itself depends on f0206, f0208 and c0194, so the only further wait is c0202 (`design: draft`, behind f0199, f0201, f0145 and f0186).
- Neither `ready` nor z-work reads the prose in a raft's Order & dependencies. Step 0 checks c0210, the pre-ready PR and the blobs, not c0202.

So once c0210 is done and c0392 is rafted, c0392 is readied and lands, and the window lasts until f0209. That is the Guess's option (a), the one the design rejects, and nothing turns red.
Critique: the tempting fix is a stronger sentence for z-raft, but z-work's choice still comes from `ready`.
Consequences: an edge on c0202 makes c0392 wait for c0202's chain (f0199, f0201, f0145, f0186 and what they wait on). f0209 already waits for all of it, so f0209 is not delayed. There is no cycle: none of those items depends on c0392 or f0209. c0202 is in no raft, so no grouped record goes stale (lesson z-design/depends-on-inherits-the-dependency-raft: name the chain). If the user rules the Guess's option (a), the edge is dropped.
Recommendation:
- Put `c0202` in `depends_on`, with a sentence saying f0206 and f0208 come through c0210.
- Add "c0202 is in `done/`" to step 0.
- Keep the Guess as the user's question about that edge.
- Say where the pre-ready PR is made. c0392.md:38 says "On main it runs `git apply`". It belongs in a worktree branched from origin/main, never the main checkout (AGENTS.md).

### F3 [medium] AC1's check that nothing outside the trackers names `lobby-start` also reads every skill's `lessons/` folder, where harvests will write that name
Where: narrow.py:116; c0392.md:48; Rules and mutants row N10.
Evidence: the pathspec excludes only `**/.tracker/**` and the script's own folder. Lessons live outside both: `z-nile/skills/<skill>/lessons/` and `<project>/skills/…/lessons/`. In a scratch repository, the same command, `git grep -l -F --untracked lobby-start -- . ':(exclude,glob)**/.tracker/**' ':(exclude)portal/tests/acceptance/c0392'`, lists `z-nile/skills/z-design/lessons/x.md`, a file holding "c0392 design review 001: lobby-start.spec removed".

This prep's harvest of this review and f0209's harvest of its own review (in flight) both land before c0392's raft runs. Harvests routinely quote the file a finding was about. AC1 is then red on a correct deletion and step 1 shows a third line. The sequestered script cannot change, so the only way out is a re-prep.
Critique: the tempting fix is to tell harvesters not to write the name. Nobody harvesting f0209's review reads c0392's design.
Consequences: lessons are records, like the tracker. Excluding them leaves skills, docs, specs, scripts and watch and inputs files covered, so a skill that told someone to run the removed file would still be caught.
Recommendation: add `:(exclude,glob)**/lessons/**` to the first grep and name it in the AC1 bullet's list of exempt records. Add a mutant N13, "a lesson file names lobby-start", that AC1 must pass. Keep N10 red, and rerun E4.

### F4 [low] E5's one red `manifest.spec` is recorded as "not explained", and the executor has no fallback for it
Where: c0392.md:98 (E5); Implementation step 3.
Evidence: E5 records "c0210's AC1 (`manifest.spec`) was red once. Its output was not kept." `manifest.spec` has no file writes, `exec` or randomness (checked by grep), so the cause was probably outside the spec: the runner's lock, or its tripwire after another session changed a ref. Nothing records which. Step 3 says only "AC1 and AC2 pass".
Recommendation: step 3 says that a red AC2 case in a c0210 spec is rerun once with its output kept, and that if it fails again the executor names the case and stops (z-work: "the same check failed after a real second attempt").
Lesson: z-design/contradicting-results-are-unknowns

### F5 [low] The Existing work bullet points at a disagreement it does not name
Where: c0392.md:70: "One of its sentences disagrees with this design, and that was reported to the session lead (the report)."
Evidence: no executor or later reader can find "the report". In f0209's current text, the one sentence that conflicts with this design is its Overrides row quoting the Non-goal: "c0210's AC3 and AC8 cover order and attributes" (f0209.md:124). E2 and E3 found that premise partly false (L1 to L5 survive AC8).
Recommendation: name the sentence and what f0209 should change, or drop the clause.

Verdict: changes
