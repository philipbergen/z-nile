# Review 005: c0121 (design mode)
Inputs: prep-c0121 13536dae (c0121.md, check.sh, acceptance/*, design-review-004.md, design-refute-004.md, the lesson notes); impl-c0121 f6563c14 (Stop fix af38e7ea); impl-c0118 97c35b43; impl-c0117 (local 626bce81, origin 434d94e1); origin/main 1e749844; `./zn lessons --when design`. Scratch clones under the reviewer's scratchpad (`dr-c0121-005/c21`: impl-c0121; `dr-c0121-005/c18`: origin/main with 434d94e1 and prep-c0118 merged, to simulate c0117 and the prep landed).
Dropped from design-review-004: F1, F2 (as stated: the branch, the lower tips and the non-unique search are fixed; the hole in F1 below is new), F3, F4

What holds, and was checked:
- **004 F1, Stop.** `serve.plan` (serve.luau:146) is `if own.outcome ~= "running" and follows and dispatchOf(m, follows) ~= nil`. On the impl clone, `guard.spec` + `server.spec`: 39 passed, 0 failed. N50 (`if follows and dispatchOf…`): 37 passed, 2 failed (guard's "stop on a member whose run follows its raft…", server's "stop on a member stops its raft's run…"), both on assertions. `check.sh` and `acceptance/` are byte-identical between prep-c0121 and impl-c0121. The fixtures no longer use `follow`/`followed`. c0117's follow branch (impl-c0117 dispatcher.luau:1406, `st.follows = action.target`) is still the only writer, unchanged by R0052's code-review commits (`git diff 434d94e1 626bce81 -- z-nile/engine/dispatcher.luau | grep -E '^[-+].*(follows|stopAt|"stopped"|"lost")'` is empty). The only live outcome c0117 writes is `running` (dispatcher.luau:930), so the rule's premise holds.
- **004 F2, the branch and the apply.** Step 1 now runs on the raft's own branch and applies `git diff $(git merge-base impl-c0118 impl-c0121) impl-c0121 -- . ':!*/.tracker/**'`. That diff is 7 files, 613 + / 8 −, c0121's code only (no counter, no lessons). Simulated in `c18` (main + c0117 + the prep + c0118's code applied and committed), `git apply -3` applies all 7 cleanly. The Overrides line says what the c0118 docs override is.
- **004 F3, F4.** §4 now says the state stays `running` until the next dispatch marks it `lost`. The Order paragraph names the six specs, and the Verification log marks the "one raft" clause superseded.

### F1 [medium] Step 1's landing search can never pass: its base is "the merge-base this prep is rebased onto after c0118 lands", which puts both c0117's and c0118's landings before the range, so "zero matching commits for a done item stops the step" always fires (third hole in step 1's mechanism: 003 F2, 004 F2)
Where: Implementation steps, step 1, **Commits** ("`<base>` is the merge-base this prep is rebased onto after c0118 lands … Zero matching commits for a done item stops the step")
Evidence:
- The search is `git log --first-parent <base>..origin/main -- <watched paths>`. The order (the Design's Order paragraph) is: c0117 lands, c0118 lands, then this prep is rebased onto main. After that rebase, `git merge-base` with main is a commit at or after both landings. So neither landing is in `<base>..origin/main`.
- The same thing, run on today's history with c0116's landing as the stand-in (the c0118 step uses the same rule):
  ```
  $ git merge-base --is-ancestor 30196933 origin/main && echo "R0050 #121 is an ancestor of origin/main"
  R0050 #121 is an ancestor of origin/main
  $ B=$(git rev-parse --short origin/main)   # a base taken after the landing, as the rebase would
  $ git log --first-parent --format='%h %s' $B..origin/main | grep -cE '^[0-9a-f]+ R0050: .*\(#[0-9]+\)$'
  0
  ```
  An executor follows the text: `./zn find c0117` and `./zn find c0118` are under `done/`, the range has no `R<id>:` commit for either, so the step stops for a re-prep on a sound branch.
- The other direction is open too. Commits between the world c0121's diff was made on and the rebase are judged only by "a rerun of this search" that the rebase records. Nothing says what the rebaser does with a non-landing commit it finds there, and no review sees that rerun. An unexpected upstream change in that window would pass unjudged.
- Until the rebase, the step names no base at all (004 F2 (d), still open).
- This came from round 004's own Recommendation ("have the rebase record the base sha"), which the refute took word for word.
Critique: this is the third hole in step 1, so the question is the mechanism. The base has two jobs, and they pull apart when a rebase moves it. One job is "the world the carried diff was made against", which is fixed. The other is "where the dependencies' landings start", which also lies before the rebase. The tempting fix is to drop the zero-match rule. Then a done dependency whose landing can't be found passes silently, which is the case `zz-arch/history-tests-survive-squash` says must stop.
Consequences:
- If the base is pinned at the world the diff was made on, the range always holds both landings, and zero matches means what it says.
- The range then grows with time. Every other item's commit that touches a watched path stops the step (c0083 is already named). That is the method's intended cost.
- The rebase no longer chooses anything. It only records a rerun, and a non-landing commit found at the rebase is a re-prep then, the same rule as at execution.
Recommendation:
- Pin the base now, in this reviewed document, as the main that impl-c0121's stack was last merged with: `git merge-base impl-c0121 origin/main` is 0a7cc743 today. c0116's landing (30196933) is before it. `git log --first-parent 0a7cc743..origin/main -- <watched paths>` is empty today.
- Say that the rebase never moves it. The rebase reruns the search from 0a7cc743 and records the output in the Verification log, and any commit other than an allowed one stops there too.
- Keep "every `R<id>: … (#<n>)` in the range, zero stops" as it is. It is now sound.
- Correct the note in `z-design/watch-steps-name-their-base` the same way (it says "name the base as a sha" and then prescribes a base taken from a branch). The base of a carried diff and of its watch is the world the diff was made on, pinned by sha. A rebase never moves it, because a base past a dependency's landing hides the landing the zero rule looks for.
- The same defect is in c0118's rewritten step 1 (c0118 design review 010 F1). Fix both together.
Lesson: z-design/watch-steps-name-their-base; zz-arch/history-tests-survive-squash

### F2 [medium] §4's "a lost own run: a second click follows" has no case, and the mutant "follow only when the card's own outcome is `ok`" passes both specs
Where: c0121.md §4 stop ("A lost own run is the one case the first click does not reach the raft's live run: its answer says `lost`, and a second click (the own outcome now `lost`) follows"); Rules and mutants rows N48 to N50; guard.spec and server.spec's stop cases
Evidence:
- The fixtures seed a followed card's own outcome only as `ok` (the follow) or `running` (a step of its own). No case has a card whose own outcome is `lost`, `failed`, `stopped`, `quota` or `tripwire` while it follows a raft with state.
- Run on the impl clone, mutant `if own.outcome == "ok" and follows and dispatchOf(m, follows) ~= nil then`:
  ```
  39 passed, 0 failed, 2 spec files
  ```
- Under that mutant, the two-click path §4 promises never reaches the raft. Take an issue whose own step was lost, or failed after it followed. Every click sends `./zn dispatch stop <issue>`, which answers "not running" (impl-c0117 dispatcher.luau:1475-1483). The raft's live run is never stopped from that card.
Critique: the rule is stated in §4 but has no Rules row, and `zz-test/seed-every-enumerated-case` asks for every value of the set the code walks. The tempting fix is one `lost` case. A `failed` own outcome takes the same branch and is as likely (a review step run on the issue after its chain followed, which then fails).
Consequences: none beyond the cases. The rule already treats every non-`running` own outcome alike.
Recommendation:
- Add a Rules row "stop follows for every own outcome but `running`", with this mutant (N51).
- In guard.spec's follow case, add a card whose own outcome is `lost` and one whose own outcome is `failed`, each following a raft with state, and each planning `dispatch stop <raft>`.
- Run N51 and record that it is killed.
Lesson: zz-test/seed-every-enumerated-case; z-design/spec-design-correspondence

### F3 [low] Step 1 names the diff's ends by branches that the process closes before the step runs, and carries `.` rather than c0121's paths
Where: Implementation steps, step 1 (the intro: "`impl-c0121` (#123) is reference only, closed when the raft's PR opens"; **Apply**)
Evidence:
- The raft's PR opens at `./zn start`, before step 1, and #123 is "closed when the raft's PR opens". z-stop's documented way to close a stale PR is `gh pr close <pr> --delete-branch`. The repository deletes a branch on merge (`gh repo view --json deleteBranchOnMerge` → `true`). So `impl-c0118` (#122, closed when c0118's raft PR opens) and `impl-c0121` aren't guaranteed to exist when step 1 runs.
- Run in `c18` with the lower ref deleted (c0118's step has the same form):
  ```
  fatal: Not a valid object name impl-c0117
  error: z-nile/engine/boardview.luau: does not exist in index
  pipe exit=1
  changed: 0
  ```
  The failure is loud and nothing is applied, but the step gives no next move.
- 97c35b43 is an ancestor of impl-c0121, so only impl-c0121 has to survive.
- The pathspec `. ':!*/.tracker/**'` is clean today (7 files). A later impl-c0121 commit that touches `z-nile/next` or a lesson would be carried and would conflict (as c0118's diff does: c0118 design review 010 F2).
Recommendation:
- Write the diff as `git diff 97c35b43 impl-c0121 -- <the Touched modules that exist in it>`.
- Say that #123 is closed without deleting its branch, and only after step 1's apply is committed. A missing `impl-c0121` stops the step, which is then fetched from `refs/pull/123/head`.
Lesson: z-design/instructions-runnable-where-they-run

### F4 [low] Stop's rule rests on c0117's `follows` contract at 434d94e1, and step 1 allows c0117's landing wholesale, so a change in R0052's remaining review isn't seen
Where: §4 stop ("c0117 writes `follows` once, at the follow, and never clears it"); step 1, **Watched paths** (no `dispatcher.luau`) and **Commits** (c0117's landing allowed)
Evidence:
- The specs feed `serve.plan` hand-written dispatch states. Nothing in `check.sh` runs c0117's code to produce one.
- R0052 is still in code review (local impl-c0117 626bce81 is two review commits past 434d94e1), and 004 F1 itself named "clear `follows` when a run starts" as a c0117-side option.
- A renamed field, or a second writer, lands as "R0052: … (#n)", an allowed commit. c0121's specs stay green against their fixtures, and the board's `follows` read goes quietly nil.
Recommendation: add to step 1 a check of the contract on the landed main. `git show origin/main:z-nile/engine/dispatcher.luau` must still declare `follows: string?` in the state type, with `st.follows =` written only in the `follow` branch, and the only live outcome `running`. Otherwise stop and escalate. One line in the step, with no spec change.
Lesson: z-design/design-the-execution-window

Verdict: changes
