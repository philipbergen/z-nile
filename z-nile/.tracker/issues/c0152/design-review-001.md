# Review 001: c0152 (design mode)
Inputs: prep `prep-merge-past-tracker-only` fe2259bf (c0152.md, check.sh, acceptance/merge-check.spec.luau, acceptance/docs.spec.luau); prototype `proto-merge-past-tracker-only` 7ff787d5 (`z-nile/engine/mergecheck.luau`, `main.luau`, zz-rules); `origin/impl-c0117` 434d94e1 (zz-rules diff); `.github/workflows/check.yml`; `./zn capture c0152`; `./zn lessons --when design --full`. A mutant and the docs specs ran in a scratch clone (scratchpad `dr-chores-1/c0152`).

### F1 [medium] "Tracker state" isn't gate-neutral: the gate reads main's new `check.sh` files and documents, and nothing tested them with the PR
Where: Design "The rule" ("GitHub's squash merge is then exactly the tree CI tested plus main's new tracker changes"); Regression guard
Evidence: `publish.allowed` accepts any `<ID>.md`, `check.sh` or `spend.md` under a root, checking the path only (`publish.luau:99-119`). The z-nile gate reads those files. c0120's promoted `check-paths.spec` (real-tree case) scans every unfinished item's `check.sh` for paths that must exist, its `finished.spec` judges finished `check.sh` files, and `audit` judges every document. On main, `check.yml` skips the gate for pushes that only touch `*/.tracker/**` and `z-nile/next`, so those commits are never gated alone either. Scenario: the PR deletes or moves `z-nile/foo`, and a capture landed on main after the PR's CI adds a `check.sh` naming `z-nile/foo`. Each side is green, yet the squash merge is red on check-paths, and only the post-merge push to main (it touches code, so CI runs) shows it. The design's claim that the merged tree is "the tree CI tested plus tracker changes" is true file by file but not gate by gate.
Critique: the capture fixes the class ("the publisher's tracker-state classes"), so narrowing it isn't the reviewer's call. The design must still state the residual risk, rather than call the merged tree tested.
Consequences: a red main after such a merge is caught by main's own CI run, at the cost of a fix PR. The ways to close it all have costs. Excluding `check.sh` creations from the exception restores a cycle for every capture or ready that lands during a PR. Running the tracker-reading gate stages (check-paths, finished, audit) locally on the would-be merge tree before merging takes seconds and keeps the exception.
Recommendation: add a Risks paragraph naming the interaction (the gate stages that read tracker files, and the example above) and the options. escalate to the user: (a) accept it, since main's CI catches it after the merge; (b) `merge-check` also runs check-paths and audit on `git merge-tree` of head and tip (one more spec case: a main `check.sh` naming a path the PR deletes says no); (c) exclude `check.sh` changes from the exception (more cycles). Record the answer as a `Decided with the user` line.

### F2 [medium] Nothing ties `<green head>` to the PR's current head, so a push after green merges untested code
Where: Design "The rule"; zz-rules Merging step 4 wording (prototype)
Evidence: `mergecheck.judge(dir, head)` takes any commit the merger names and never asks GitHub which head is the PR's or whether it is green. Step 4 then merges with `gh pr merge <pr> --squash`, which takes whatever head the PR has at that moment. A merger who pushed a fixup after CI went green (or another session pushing to the branch) can run `./zn merge-check <the green sha>`, get ok, and squash an untested head. c0117 (impl-c0117 zz-rules, "The chain") closes the same gap for its gates with `gh pr merge --squash --match-head-commit <head>` and a head read from `refs/pull/<n>/head`.
Critique: the exception skips the step that used to re-establish "CI is green at what merges". The pin has to move into the exception itself.
Consequences: with `--match-head-commit`, a push after the check voids the merge (GitHub refuses), and the merger re-runs merge-check after the next green CI. That is the intended behaviour, and the skill should say so.
Recommendation: step 4's exception merges with `gh pr merge <pr> --squash --match-head-commit <the head merge-check judged>`, and its ok line prints the full sha to pass. Pin both in docs.spec. Optionally, `merge-check` takes the PR number and reads its head (`gh pr view --json headRefOid`) and CI state. If so, add a fake-gh case.

### F3 [medium] The first-parent rule for merge commits has no case: dropping it passes the spec
Where: Design ("A merge commit on main is judged by its first-parent diff"); merge-check.spec; Rules and mutants
Evidence: mutant on the prototype, `diff-tree … "-m", "--first-parent", c` → `diff-tree … c` (on a merge commit plain `diff-tree` prints nothing): `merge-check.spec` `5 passed, 0 failed`. With that mutant, a merge commit on main whose own changes (a conflict resolution, an evil merge) touch code is judged clean whenever its second parent's commits are already reachable from the head.
Critique: lesson z-design/spec-design-correspondence: a Design sentence with no failing case.
Consequences: none beyond the fixture. The case needs a merge commit on origin's main.
Recommendation: add a case: origin's main gains a merge commit whose merge changes a code file not in either parent, and whose second parent is a tracker-only branch. Expect no, naming the merge commit and the path. Add a Rules row with this mutant.
Lesson: z-design/spec-design-correspondence

### F4 [medium] Once c0117 lands, a second definition of tracker state exists for merge gates
Where: Design "Where" (`publish.allowed`), Overlap paragraph, Non-goals
Evidence: impl-c0117's zz-rules adds "**Tracker state** has one definition (`z-nile/engine/trackerstate.luau`), which the wrapper, the broker, the tripwire, the watermark and the merge gates all use". That definition is stricter than `publish.allowed`. It works on the raw diff, regular files only, and sequestered files judged per item ("unchanged or, when the item's folder moved, as `paths.rewrite` writes it; only a new item adds them"). Under `publish.allowed`, a main commit that edits an existing item's `check.sh` is tracker state. Under c0117's definition it isn't. The Overlap paragraph discusses only hunks in `main.luau` and the skill, and says c0117 "could call `merge-check` later", not that the two definitions disagree. Lesson zz-arch/one-definition-of-tracker-state is cited for `publish.allowed`, but c0117 is about to move that one definition.
Critique: whichever lands second leaves two merge gates with different meanings of tracker state, contradicting c0117's "one definition" sentence (lesson z-design/restated-rules-move-together).
Consequences: if mergecheck switches to `trackerstate` once it exists, a main commit that edits an existing `check.sh` becomes no, which tightens F1 too.
Recommendation: in the Overlap paragraph, say that mergecheck takes c0117's `trackerstate` function when c0117 lands first, and that c0117's lead switches mergecheck if c0152 lands first. Add the c0117 dependency or order to the note for z-raft. Add a spec case that a main commit editing an existing item's `check.sh` gives the same verdict under both orders, chosen now.
Lesson: z-design/design-the-execution-window

### F5 [low] Failed git reads in `judge` count as "nothing found"
Where: prototype `mergecheck.judge` (`local _, prFiles = git(… "diff" …)`, `local _, revs = git(… "rev-list" …)`, `local _, files = git(… "diff-tree" …)`)
Evidence: each of these three discards the exit status. A failing `rev-list` gives `count = 0` and "moved by 0 commit(s) … ok". A failing PR diff gives no overlap, and a failing `diff-tree` gives a clean commit.
Critique / Consequences: lesson zz-arch/guard-no-is-explicit: ok must be one explicit answer. None.
Recommendation: the Design states that any failed git read is a no naming the command. The spec gets one case (for example a head whose merge-base is reachable but a `rev-list` over a missing object, or a stubbed git) or a reasoned row.
Lesson: zz-arch/guard-no-is-explicit

### F6 [low] The full gate wasn't rerun after the read-only-list fix
Where: E1
Evidence: E1 records the full gate at 1221/1 on the first prototype commit. After 7ff787d5 moved `merge-check` in the list, only c0116's and c0152's docs specs were rerun. I ran the 13 promoted specs that read `zz-rules/SKILL.md` (`git grep -l "zz-rules/SKILL.md" -- z-nile/tests`) on 7ff787d5, and all pass, so no defect follows.
Recommendation: rerun `z-nile/check.sh --project z-nile --full` on the final prototype before the prep commit, and record it.
Lesson: z-design/rerun-skipped-checks-after-edits

Candidate lessons (for the lead):
- z-design: "tracker-only" means unreviewed by CI, not unread by it. When a rule skips CI because changes are in tracker files, list the gate stages that read those files and say how their interaction with the PR is covered; check: does any gate stage read the paths the exception lets through?
- zz-arch: an exception that skips re-verification must pin what it verified to what gets merged (`--match-head-commit`); check: can the merged commit differ from the one the check judged?

Verdict: changes
