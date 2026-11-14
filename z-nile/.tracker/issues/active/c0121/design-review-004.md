# Review 004: c0121 (design mode)
Inputs: prep-c0121 94baefd4 (c0121.md, check.sh, acceptance/*, design-review-003.md, design-refute-003.md, harvest.md, the three lesson changes); impl-c0121 4d6138e9 (the F3 code change); prep-c0118 195858d8 (G9); origin/main; `./zn lessons --when design`. Scratch clones of impl-c0121 and prep-c0121 under the reviewer's scratchpad (`dr-c0121-004/`).
Dropped from design-review-003: F1, F4, F6 (fixed as refute 003 says), and F3 as stated (its two cases are fixed; the hole below is new).

What holds, and was checked:
- **F1, the order.** `solo: true`, the Decided line, the Order paragraph and #119's body all say c0118 lands first, then #119, then c0121 alone. prep-c0118 195858d8's G9 no longer names c0121 as a raft partner. `check.sh` and `acceptance/` are byte-identical between prep-c0121 and impl-c0121 (`git diff --stat prep-c0121 impl-c0121 -- …/check.sh …/acceptance` is empty).
- **F3, as specified.** On the impl clone, `guard.spec` and `server.spec`: 39 passed, 0 failed. N48 (`target = id`) fails 2 cases (guard's follow case, server's member case). N49 (no 409: a card with no state gets a stop) fails 2 cases (guard's 409 case, server's case). A third mutant, "follow without checking that the target has state" (`if follows then`), fails guard's stale-follow case. All three are killed on an assertion.
- **F4.** On the prep clone at 94baefd4, c0120's `check-paths` gives 3 passed, 1 failed, and it now lists six c0118 paths (`docs`, `history`, `model`, `page`, `real`, `view`). The docs spec is no longer hidden. Of the Touched paths, `z-nile/tests/lib/cachepaths.luau` and the five engine and doc paths exist on origin/main. `z-nile/tests/acceptance/c0118`, `…/c0121` and `z-nile/engine/serve.luau` don't exist yet, which is expected.
- **F6.** #119's body has the order, the expected reds, the three rounds and the 47 + 2 mutants.
- **New lessons.** `z-design/dependent-specs-sequence-the-preps` is a lesson another raft could fail (any item whose `check.sh` runs another item's promoted specs). It is not a restated finding. `zz-arch/act-on-the-id-the-state-follows` is general too, but its "stale pointer" test is incomplete: see F1. The note added to `watch-steps-name-their-base` prescribes a landing search that isn't unique: see F2.

### F1 [medium] Stop's follow rule trusts a `follows` pointer that c0117 never clears: Stop on an issue running a step of its own is sent to its raft, and stops the raft's run if that one is live
Where: c0121.md §4 stop ("the target is the `follows` id when that id has state too, else the card's own id"); impl-c0121 `serve.plan` (serve.luau, `if follows and dispatchOf(m, follows) ~= nil then target = follows`); guard.spec's MODEL (f0021's dispatch)
Evidence:
- **c0117 writes `follows` once and never clears it.** `git grep -n follows impl-c0121 -- z-nile/engine` lists one writer, `dispatcher.luau:1376` `st.follows = action.target` (the chain's `follow` branch). That branch sets nothing else on the issue's state, so the step and outcome stay those of the issue's last step, which ended `ok`. `retry` resets only `st.outcome, st.detail` (dispatcher.luau, `first == "retry"`). `loadAt` returns the saved table whole.
- **A step of the issue's own runs on that same state.** `./zn dispatch <step> <id>` (`oneStep` → `dispatcher.top`, dispatcher.luau:1590-1625) does `load(ctx, key)` on `.cache/dispatch/<id>/`, the issue's top folder. It then marks it `running` (modelStep, `st.outcome … = "running"`; save). Take an issue whose chain followed its raft, and run a review or design step on it (`./zn dispatch zz-review f0021 --mode design`). Its state is now `outcome = running, follows = R0020`, and R0020 has state.
- **Run in the impl clone.** `serve.plan` on a model where f0021's dispatch is `{ step = "z-raft", outcome = "running", follows = "R0020" }` and R0020's is `{ outcome = "stopped" }`:
  ```
  $ lune run .cache/probe/p.luau
  dispatch stop R0020 nil
  ```
  - With R0020 stopped, the click answers 200 "not running" while f0021's step keeps running. That is design review 003 F3's defect again.
  - With R0020's `z-run` live, the click kills the raft's run, which the user never asked to stop.
- **The fixture shape doesn't exist.** guard.spec's and server.spec's followed issue has `step = "follow", outcome = "followed"`. `git grep -n '"followed"' impl-c0121 -- z-nile/engine` is empty: c0117 never writes either value. So the fixture can't show what the rule reads on a real followed state (the last step, `ok`).
Critique: this is the second hole in how Stop picks its id, so the question is the mechanism. "The pointer's target has state" only tells you the target existed once. It doesn't tell you the issue's own run is idle. The tempting fix is to compare `follows` with the item's current `raft:`. That fails here, because the issue is still in R0020.
Consequences:
- The only writer of `follows` leaves the issue's own outcome at its last finished step. So an own outcome of `running` always means a step of the issue's own is live, or was lost.
- Stopping the issue's own id when it says `running` is therefore always right. c0117's `stopAt` stops the issue's run if it is live, or marks it lost if it isn't. Nothing is ever sent to the raft by mistake.
- A lost own run is the one case where the raft's live run isn't reached by the first click. The answer's text (`lost`) says so, and a second click (own outcome now `lost`) follows to the raft.
Recommendation:
- In §4 and `serve.plan`: with no state for the card, answer 409 (as now). When the card's own outcome is `running`, stop the card's own id. Otherwise, stop the `follows` id when it has state, else the card's own id.
- Seed the followed fixtures from c0117's real shape: the issue's last step with outcome `ok`, plus `follows`. Never use `follow`/`followed`.
- Add a case to guard.spec: an issue running its own step whose state follows a raft with a running run plans `dispatch stop <issue>`. Add the same to server.spec's runs.
- Add a Rules row with mutant N50, "follows wins over an own running step".
- Add a note to `zz-arch/act-on-the-id-the-state-follows`: a pointer written once is current only while the source's own state says its run moved. Check the source's own state first, not only that the target exists.
- A c0117-side alternative is to clear `follows` when a run starts on the id. That changes R0052, which is in review, so prefer the c0121 rule.
Lesson: zz-arch/act-on-the-id-the-state-follows

### F2 [medium] Step 1 still can't be run as written (repeat of design-review-003 F2): the tooling never puts the raft on impl-c0121, "the landed impl-c0118 tip" isn't what c0118 lands, and the landing search matches more than one commit
Where: Implementation steps, step 1 (the intro, "Before the merge", "Commits"); the note added to `z-design/watch-steps-name-their-base`
Evidence:
- **(a) The branch.**
  - `./zn worktree R<id>` creates `raftBranch(raft)` (`R<id>-<slug>`) from `origin/main`: main.luau `cmd.worktree`, `git worktree add --no-track -b <branch> <path> origin/main`.
  - `./zn start` then refuses unless the worktree is on that branch: `branch {branch} already exists: switch to it and run start there`, or `switch -c`. It then opens a **new** draft PR.
  - The prompt the executor follows starts with `cd "$(./zn worktree R<id>)"` and `./zn start` (R0052's prompt.md, line 18). So the executor is on `R<id>-<slug>` with no `serve.luau` and a PR that isn't #123.
  - Step 1 then says "merge `origin/main` into `impl-c0121`", a branch the executor isn't on. R0052, the precedent cited, hasn't started (no `R0052-*` branch exists) and says only "read it by commit".
- **(b) The lower branch's tip.** c0118 lands from its own raft branch through the same `worktree`/`start` route, and its code-review fixes are committed there. "Merge … the landed impl-c0118 tip into impl-c0121" merges a branch that lacks those fixes. The merge of main then conflicts in c0118's hunks, and step 1 stops on a sound branch.
- **(c) The landing search isn't unique.**
  ```
  $ git log --first-parent --format='%h %s' origin/main | grep -E '^[0-9a-f]+ R0035:'
  577b8a6a R0035: Ghost hunter tools (#114)
  5de93de8 R0035: Ghost hunter tools (#106)
  ea1009ce R0035: prep Ghost hunter tools (#89)
  ```
  Three commits start `R0035:` and end `(#<n>)`, one of them a prep. "Its landing is the first-parent commit…" picks one of them, and a second landing (a fix-up raft PR) is then "any other commit" and stops the step.
- **(d) The base.** It is "written here" by the rebase, after review, so the reviewed step names no sha.
Critique: the step carries two unsquashed lower branches inside impl-c0121 and asks the executor to keep them in step with whatever lands. Every fix that lands only on a lower raft branch breaks it. The tempting fix is to add a `git reset --hard impl-c0121` before `./zn start`. That still carries the stale lower copies.
Consequences: if c0121's own delta is applied on top of main, conflicts arise only where the landed c0117/c0118 changed c0121's touch points, which is exactly what the step should judge. #123 becomes reference only, and is closed when the raft's PR opens.
Recommendation:
- Rewrite step 1 so the raft runs on its own `R<id>-<slug>` branch, made by `./zn worktree`/`start` from origin/main after c0118 is done. The step applies c0121's own delta: `git diff $(git merge-base impl-c0118 impl-c0121) impl-c0121 -- . ':!*/.tracker/**' | git apply -3` (today the merge-base is 97c35b43, and the diff is the 578 lines `size` counts). A conflict is allowed only in c0121's own hunks, as listed now. Drop the "merge the lower tips" bullet.
- Allowed landings are every first-parent commit whose subject matches `^R<id>: ` and ends `(#<n>)`, for each R<id> holding c0117 or c0118 under `done/`, prep PRs included. Zero matches for a done item stops the step (lesson `zz-arch/history-tests-survive-squash`: "pin nothing for zero or two matches").
- Have the rebase record the base sha and a rerun of the commit search in the Verification log, as part of the prep PR that lands after c0118.
- Correct the `watch-steps-name-their-base` note the same way: every matching commit, and zero stops.
Lesson: z-design/instructions-runnable-where-they-run; zz-arch/history-tests-survive-squash

### F3 [low] §4's corrected account of a server killed by `kill <pid>` is wrong the other way: the error comes before the step's outcome is saved, so the state stays `running` and the next dispatch marks it `lost`
Where: c0121.md §4 retry ("exits with an error at its next output line, the step's real outcome recorded, never `lost`")
Evidence:
- After the CLI ends, `modelStep` prints `dispatch: {step} on {cli}: …` (dispatcher.luau:961) before it sets `st.outcome = outcome` (1076) and calls `save(st)` (1083).
- The review's landing move (around 1045) and the spend rows come after that print too.
- Nothing between catches it: `chain` calls `modelStep` directly, and `top`'s `pcall(body, st)` unlocks and re-raises.
- Run in scratch: a Lune script that writes `state=running`, waits 1 s, prints, then writes `state=ok`, run as `lune run s.luau | true`:
  ```
  Broken pipe (os error 32)
  … Line 5
  exit=1 state=running
  ```
- So the step's state stays `running` with a dead dispatcher. The next `./zn dispatch <id>` marks it `lost` (`top`: "its dispatcher died mid-step"). A finished review stays in the state folder unplaced.
Critique: round 003 inferred this from the code without running it, and the refute adopted the inference. The user-facing effect is that a pid-killed server leaves a finished step to be redone by `retry`.
Recommendation:
- Rewrite the sentence: "a `kill` of the server's pid alone leaves the retry's current step running to its end. The dispatcher then dies at its next output line, before it records the outcome, so the state shows `running` until the next `./zn dispatch <id>` marks it `lost`, and `./zn dispatch retry <id>` runs the step again."
- Optionally (the author's call; G3 is unaffected, because Ctrl-C still reaches the group), the server could send a retry's output to a file (`.cache/board/retry-<id>.log`) and read the first second from there. A killed server then strands nothing. That needs one server.spec case and a Rules row.
Lesson: zz-review/run-the-evidence-you-cite

### F4 [low] Two sentences still say what the fixes changed
Where: Design, the Order paragraph; Verification log, the "Rechecked 2026-10-25" bullet
Evidence:
- The Order paragraph says check-paths flags "those five promoted c0118 specs". The run above lists six, the docs spec included since F4's re-spelling (the refute says so).
- The recheck bullet still says "z-raft rafts it, the user having allowed c0118 and c0121 in one raft". That contradicts the Decided line and `solo: true` a few lines up.
Recommendation:
- Say "six" (or name the six) in the Order paragraph.
- Strike the "allowed in one raft" clause, or mark it superseded by the 2026-10-25 decision.
Lesson: z-design/restated-rules-move-together

Verdict: changes
