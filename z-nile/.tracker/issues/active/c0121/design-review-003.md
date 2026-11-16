# Review 003: c0121 (design mode)
Inputs: prep-c0121 082f2044 (c0121.md, check.sh, acceptance/*, design-review-002.md, design-refute-002.md, harvest.md); impl-c0121 8bf0e3cd (PR #123); impl-c0117 626bce81 (R0052, two commits past #125's reported head 434d94e1); prep-c0118 94f94423; origin/main b9fb7cf9; `./zn lessons --when design --full`; `./zn capture c0121`. Scratch clones of all three branches under the reviewer's scratchpad (`dr-c0121/`).
Dropped from review-002: none to drop. F1 to F3 are fixed as refute 002 says. `Options.listen` and its case are on impl-c0121, and §4 has the `RETRY_WAIT` text. impl-c0121's `serve.luau` differs from `prototype.patch`'s in one line only (the vendored marked read from the top), so round 002's live attack results still apply. `bash check.sh` on the impl clone gives 5/6: AC1 to AC5 pass, and AC6 is red only because `tests/acceptance/c0118/*` doesn't exist until c0118 is done.

What holds, and was checked:
- **Watched paths.** All six exist on origin/main (`git cat-file -e`). The base f836db46 is `git merge-base prep-c0121 origin/main`. `git log f836db46..origin/main -- <watched>` is empty today. Neither prep-c0118 nor prep-c0121 touches a watched path (`git diff --stat origin/main...prep-c01xx -- <watched>` is empty for both).
- **Size.** `size: 600` matches `git diff --shortstat impl-c0118...impl-c0121 -- . ':!*/.tracker/**'`: 7 files, +578 / -7. Under the policy (`raftplan.CAP = 1500`), 1350 + 600 doesn't fit in one raft. The prepared chore rafts R0030 and R0039 have members with no `size:`, so they take nothing, and raft-plan alone puts c0121 in a raft of its own.
- **Board row.** c0118's sequestered `docs.spec` on impl-c0121 passes both row cases (G6's ready/run words are kept). Its only red is the README "(c0121, planned)" assertion, which is the declared override. c0121's override text is a substring of c0121's own README line.

### F1 [high] c0121 can't follow the route its log names: its prep fails z-nile's gate until c0118 is done, and a raft holding both c0118 and c0121 can never pass `./zn done`
Where: c0121.md Verification log, last bullet ("c0121 reaches `prepared` … and z-raft rafts it, the user having allowed c0118 and c0121 in one raft"); check.sh AC6; Regression guard `Overrides:`; c0118.md G9 ("z-raft may raft it … with another prepared chore such as c0121")
Evidence:
- **(a) The prep turns the gate red.** On a scratch clone of prep-c0121 at 082f2044, `cd z-nile && lune run tests/run -- tests/acceptance/c0120/check-paths.spec.luau` gives `3 passed, 1 failed`: `z-nile/.tracker/issues/c0121/check.sh: tests/acceptance/c0118/{history,model,page,real,view}.spec.luau (from z-nile)`.
  - check-paths is a promoted z-nile spec, so once #119 targets main its gate is red until c0118 is done. Today CI on #119 and #123 shows `skipping`, because both are stacked PRs.
  - Until the prep lands, c0121 can't become `prepared` on main. It is also still `new-copper-quiet-mellow` on main, with no `preparing` claim, and `./zn status c0121 prepared` refuses unless the issue is `preparing` on origin/main (z-design step 5).
- **(b) A combined raft is self-contradictory.** If the gate were bypassed and z-raft grouped c0118 with c0121 (G9; `z-raft c0118 c0121` overrides the cap):
  - c0118's sequestered `docs.spec` asserts `has(text, "`./zn board --serve` (c0121, planned) serves the same page live") == true`.
  - c0121's `docs.spec` asserts `has(text, "c0121, planned") == false`.
  - Inside one raft, c0118's spec is still sequestered under `active/c0118/acceptance/`, so the override ("changes it in its own raft") can't be made: zz-execute's sequestration diff allows only R100.
  - AC6 also names `tests/acceptance/c0118/*.spec.luau`, but `cmd.done` (main.luau, `if not runCheck(raft) then fail(…)` before the promotion loop) runs every check.sh before it promotes anything. AC6 would load-fail as it does on the prep clone (`could not resolve child component "c0118"`).
  - So `./zn done` of a raft holding both always refuses.
Critique: the design's only working order is "c0118 is done, then c0121's prep lands, then c0121 is rafted without c0118". The document claims the opposite: a route through `prepared` now, and a combined raft that the user allowed. The tempting fix is to delete the "allowed in one raft" clause.
Consequences:
- The user's G9 on c0118 names c0121 as its example partner, and c0118's prep doesn't know this is impossible. An unattended z-raft (or c0117's chain, which runs `raft-plan --apply` then z-raft for a prepared raftless issue) could still try to group them by argument.
- Holding #119 until c0118 is done also means prep-c0121 must be retargeted to main and rebased on c0118's landing. Step 1's base, f836db46, then changes. See F2.
Recommendation: escalate to the user:
- **(1) Sequence the two.**
  - Say in c0121.md that its prep PR lands only after c0118 is done (check-paths, with the 5 paths above, stays red until then), and that c0121 is never rafted with c0118.
  - Correct c0118's G9 example through c0118's lead, since "such as c0121" can't hold.
  - Record c0121 as `solo: true`, or say why a raft of its own without it is safe. c0121's `depends_on` already blocks `ready` until c0118 is done, but z-raft could fold it into another chore raft and block that raft's other members.
  - Cost: c0121 waits for c0118's whole execution.
- **(2) Make one raft possible.**
  - AC6 finds c0118's specs wherever they are (`$(./zn find c0118)/acceptance` before done, `tests/acceptance/c0118` after), spelled from `$PWD` so check-paths reads no literal.
  - c0118's own prep changes its README assertion to accept either form. That is a c0118 design change needing a c0118 review round, and the lesson z-design/finished-overrides-land-before-ready applies to the sequestered side.
  - Cost: re-opening c0118's approved design.
- Either way, add a Verification-log line with the check-paths run above and the order chosen.

### F2 [medium] Step 1 can't be run as written: its "after the merge" check fails before steps 2 to 8 exist, it doesn't say which branch the raft runs on, and it identifies c0118's landing by a PR number c0118 may never land under
Where: Implementation steps, step 1 (the Commits and After-the-merge bullets)
Evidence:
- **(a) The check after the merge.** Step 1 ends "`bash "$(./zn find c0121)/check.sh"` and `z-nile/check.sh --full` pass, else stop". On the prep tree, before any implementation, check.sh is `0/6 criteria passed` (scratch clone, 082f2044).
  - A raft branch made by `./zn start` from origin/main has no serve.luau, so step 1 stops every time.
  - The step was copied from c0118's, which says "must pass by the end of step 6".
  - It would only pass if the raft branch were impl-c0121 (#123), as R0052's Whole-raft design names `impl-c0117`. c0121.md mentions impl-c0121 only as a line count, and no raft exists to say so.
- **(b) c0118's landing commit.** The allowed commits are "the squashes of #125 and #122". c0118 isn't rafted. If its raft lands from a branch other than `impl-c0118`, its squash isn't `(#122)` and step 1 stops on c0118's own landing. c0118's step names its allowances by subject suffix (`(#121)`, `(#125)`), and c0121's names no way to recognise them at all.
- **(c) Unrelated commits.** Any other commit on a watched path forces a re-prep. A search shows one live candidate today: `for f in <unfinished z-nile issue docs on origin/main>; do <Touched section> | grep -E 'engine/main.luau|zz-rules/SKILL.md|engine/board|README.md|cachepaths'` → `c0117` (R0052, allowed) and `c0083` (`z-nile/skills/zz-rules/SKILL.md`, prepared in R0030). If R0030 lands first, step 1 escalates. That is the method's intended cost, but it should be named.
Critique: an executor following step 1 literally escalates on a sound branch. The tempting fix is to soften the After-the-merge line to "by the end of step 7". That still leaves the branch question open.
Consequences: if the raft runs on impl-c0121, impl-c0121 already holds c0118's and c0117's unsquashed commits. Merging their squashes is clean only if impl-c0121 last merged the same impl-c0118 and impl-c0117 that landed. impl-c0121 lacks R0052's code-review fixes fc6de5a2 and 626bce81 today (`git merge-base --is-ancestor` says no), so every later fix to either lower branch must reach impl-c0121 before the landing. Otherwise the conflict sits in c0117's or c0118's hunks, and step 1 stops.
Recommendation:
- Name the branch: the raft runs on `impl-c0121`, as R0052 does, or on a fresh `R<id>-…` branch with impl-c0121 as reference only.
- Move the passing requirement to the end of step 7, as c0118 did.
- Identify c0117's and c0118's landings by their raft: the done raft holding the id (`./zn find c0118` under `done/`, its `R<id>`), and the first-parent commit on main whose subject starts `R<id>:` and ends `(#<n>)`. Never use a PR number fixed now.
- If the raft runs on impl-c0121, add "merge the landed impl-c0118 tip into impl-c0121 before step 1's merge of main".
- List c0083/R0030 as a known stop.
- Re-base the step on the new merge-base once F1's order is chosen.

### F3 [medium] Stop on a member card of a running raft answers 200 "not running" and stops nothing, and Stop on any card with no run creates dispatcher state for it
Where: §4 stop ("runs `./zn dispatch stop <id>`"), §6 (each card's buttons send `{ action, id }` with the card's own id), `serve.plan` (an id is valid when it is a key of `model.home`)
Evidence:
- **How c0117 keys a run.** A chain started on an issue moves its run to the raft once the issue is rafted or active: `dispatch.luau:333-334` returns `{ kind = "step", step = "follow", target = f.raft }`. The chain then locks and writes `.cache/dispatch/<R-id>/` (dispatcher.chain, the `follow` branch), leaving the issue's own state at `follows = <R-id>`.
- **Run in a scratch clone of impl-c0117 at 626bce81**, with `.cache/dispatch/R0099/state.json` (outcome running) and `.cache/dispatch/c0999/state.json` (follows R0099):
  - `./zn dispatch stop c0999` prints `dispatch: c0999 (…/c0999): not running` and exits 0.
  - `./zn dispatch stop c0888` (an id with no run) exits 0 and creates `.cache/dispatch/c0888/` with `state.json` and a `stop` marker. `runsUnder` always includes the folder itself, and `stopAt` writes the marker and saves.
- **What the user sees.** Clicking Stop on c0999's card answers "stop: 200 dispatch: c0999 …: not running" while R0099's step keeps running. Each stray Stop leaves a state folder that c0118's card and c0121's `keyOf` then read.
Critique: the page offers a Stop that doesn't stop the run the card belongs to. The tempting fix is to hide Stop on member cards. That drops the action from the cards where users look, and it misses an issue whose own chain is mid-prep.
Consequences:
- Resolving the id needs the dispatcher's `follows` field, or the item's `raft:` while it is active, read through c0118's model (one reader).
- A follow chain can only point forward (issue → raft), so one hop is enough. A stale `follows` (the raft done) must fall back to the card's own id.
Recommendation:
- `serve.plan` acts on the card's run id: the `follows` id when the card's dispatch state has one, else the item's own id. Never run `dispatch stop` for an id whose `.cache/dispatch/<id>/state.json` doesn't exist: answer `409 nothing is running for <id>` instead.
- Retry keeps the card's own id. Its chain follows by itself.
- Cases in guard.spec: a member whose state follows its raft plans `dispatch stop <R-id>`; a card with no state plans nothing and answers 409.
- Rules rows and mutants: "stop acts on the card's own id", and "stop runs for an id with no state".
- Add the line to the zz-rules board row.

### F4 [medium] Touched modules spells three paths from z-nile's home, not from the repository, so they match nothing on the tree, and one hides c0118's docs spec from check-paths
Where: Touched modules: `tests/lib/cachepaths.luau`, `tests/acceptance/c0118/docs.spec.luau`, `tests/acceptance/c0121`
Evidence:
- `git cat-file -e origin/main:tests/lib/cachepaths.luau` fails, while `z-nile/tests/lib/cachepaths.luau` exists. Step 1 itself spells it `z-nile/tests/lib/cachepaths.luau`.
- impl-c0121 changes `z-nile/tests/lib/cachepaths.luau` (`git diff --stat impl-c0118...impl-c0121`), which no Touched entry matches.
- check-paths (F1's run) lists 5 c0118 paths. The sixth, `tests/acceptance/c0118/docs.spec.luau`, is exempt only because the home-relative Touched entry matches the check.sh literal exactly. With the entry spelled `z-nile/…` it would be listed until c0141 lands.
- Nothing else is hidden. The other entries exempt no literal in check.sh (`tests/acceptance/c0121` appears only as `$PWD/tests/acceptance/c0121`, which carries a `$`).
Critique: spend attribution and raft-plan overlap match repository-relative prefixes, so c0121's cachepaths line goes unattributed. The exemption isn't a vacuous pass: AC6 load-fails on the missing spec. But it hides one of F1's reds from the gate that shows them.
Consequences: re-spelled, the docs entry is exempt again only once c0141 lands. Under F1 option (1) the paths exist before the prep lands, so nothing needs the exemption.
Recommendation: spell all three entries from the repository root (`z-nile/tests/lib/cachepaths.luau`, `z-nile/tests/acceptance/c0118/docs.spec.luau`, `z-nile/tests/acceptance/c0121`), and rerun check-paths after F1's order is settled.
Lesson: z-design/touched-paths-exist

### F5 [low] §4's account of a `kill` of the server's pid is wrong: Lune doesn't die of SIGPIPE, and the dispatcher writes only between steps, so the step runs to its end and is never marked lost
Where: §4 retry ("a `kill` of the server's pid alone leaves the child writing to a closed pipe, so it dies at its next write and c0117 marks it lost the same way")
Evidence:
- **Run in scratch:** `lune run pipe.luau | true`, where the script waits 1 s and then prints under `pcall` five times. Every print returned `ok=false Broken pipe (os error 32)`, and the script ran on to write `survived all prints`. Lune raises EPIPE as a Luau error, not a signal.
- **Where the dispatcher prints.** `dispatcher.chain` prints only at each action (`print(describeAction(action))`). A model step can run for its whole `max_minutes` with the dispatcher alive, holding its run lock and the supervisor's lifeline.
- **What happens next.** The error at the next print escapes through `dispatcher.main`'s re-raise after the step finished. The state then holds that step's real outcome, never `lost`.
Recommendation: rewrite the sentence: "a `kill` of the server's pid alone leaves the retry running until its current step ends, and it exits with an error at its next output line. Stop it with `./zn dispatch stop <id>`." The Ctrl-C and closed-terminal account is right, because SIGINT/SIGHUP reach the dispatcher and the supervisor's INT/HUP handler kills the group (c0117 §runner).

### F6 [low] PR #119's description is stale: it says G1 to G7 are pending, that no design review has run, and that the branch's full gate passed
Where: PR #119 body (head 082f2044)
Evidence: the body says "The Guess list G1 to G7 is pending the user. No design review has run yet.", "34 of 34 mutants killed" and "This branch: full gate passed". The document records G1 to G7 as decided on 2026-10-24, two review rounds, 47 mutants, and (F1) a check-paths red on this branch.
Recommendation: refresh the body with the decided guesses, the rounds, the 47 mutants, and the expected reds (AC6, and c0120 check-paths, until c0118 is done) with the order F1 settles.

Verdict: changes
