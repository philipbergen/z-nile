# Review 006: c0121 (design mode)
Inputs: prep-board-server 3c956fb3 (c0121.md whole, check.sh, the five acceptance specs, `acceptance/overrides.sh`, `acceptance/overrides.patch`, harvest.md; `git diff 3993dca2 3c956fb3`); proto2-c0121 fa44f524 (`git ls-remote origin refs/heads/proto2-c0121` → fa44f524…, = local `proto2-c0121` and `origin/proto2-c0121`); origin/main bdec0da0 (after `git fetch origin main`; since 3993dca2 it changed tracker files only: c0265, c0269, R0087). Model: c0118's re-prep (done/c0118/c0118.md step 1, its design reviews 012 to 015, `z-nile/tests/acceptance/c0118/overrides.sh`). Scratch clone `.cache/r006-replay` of the prep worktree (`git clone`, push URL `/dev/null`, its own identity, removed afterwards): branch `raft` = bdec0da0 + the prep's c0121 folder (`git archive 3c956fb3`, the prep as it lands) + an empty start commit + step 1's apply. Probe scripts `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/{replay,ac7,mut,window}.sh`, each run through `./zn run --time …`.
Round 1 of the re-prep (G8): the first prep's rounds are 001 to 005.

## What holds (run)
- **Pins**: `git merge-base --is-ancestor 3993dca2 origin/main` → yes; `git merge-base --is-ancestor fa44f524 origin/proto2-c0121` → yes; `git log 3993dca2..fa44f524` is the one commit `fa44f524 proto2 c0121: …`, and `git diff --stat 3993dca2 fa44f524` changes exactly step 1's 8 paths (614+, 9−).
- **Step 1 replayed on today's main**: every non-new watched path exists on origin/main, `serve.luau` does not; `git diff 3993dca2 fa44f524 -- <8 paths> | git apply -3` → rc 0, all clean (serve.luau through "Falling back to direct application", as a new file must), and the tree equals fa44f524 on the 8 paths (`git diff --stat fa44f524 -- <8 paths>` empty). `git log --first-parent 3993dca2..origin/main -- <watched paths>` lists nothing.
- **c0117's contract** on origin/main's dispatcher (unchanged since R0052 e8c832ff): `follows: string?` at 73, the one writer `st.follows = action.target` at 1848, `"running"` written only at 986.
- **Checks**: `./zn check c0121` in `.worktree/proto2-c0121` → 7/7 (AC7 printing `https://github.com/philipbergen/pickman.git`); `bash check.sh` in the replayed clone (today's main + prep + apply) → 7/7. c0117's `dispatch-cli.spec` alone on the prototype → 25 passed, 0 failed (load 15), so the log's one failure in the full gate reads as the stall it says.
- **Scanners**: c0120 `check-paths.spec` on the prep worktree → 4 passed, 0 failed. On a simulated `done` of the replayed branch (acceptance moved to `z-nile/tests/acceptance/c0121`, folder to `issues/done/c0121`): `check-paths`, `finished`, c0047 `override-check`, c0077 `cache-paths`, c0049 `spec-isolation`, `repo-fence` → 34 passed, 0 failed; the promoted `overrides.sh` → rc 0.
- **AC7 windows** (`ac7.sh`; overrides.sh is c0118's final script with only the file list, the labels and the fixture name changed, `diff` checked):

  | window | rc | right? |
  |---|---|---|
  | S1 implemented | 0 | yes |
  | S2 start commit only (unimplemented) | 1 "differs from the merge base plus the reviewed hunks" | yes |
  | S3 HEAD = main + prep, nothing started | 1 "HEAD is already part of main" | yes (fixes c0118 015 F2) |
  | S6 one extra line in docs.spec / S9 the override reverted | 1 / 1 | yes |
  | S4 main edits docs.spec on another line: not merged / merged | 0 / 0 | yes |
  | S5 main rewrites the hunk's own line: not merged / merged | 0 / merge conflict in docs.spec | fail-closed (step 1: a conflict there stops) |
  | S7 squash landing: on the raft / on the new main | 0 / 1 | yes; dead after `done`, as c0118's |
  | S8 merge-commit landing, on the raft | 1 "already part of main" | yes (nobody reruns it) |
  | S11 after a simulated `done` | 0 | yes |
  | unknown tip / unreachable origin | 1 / 128 | fails closed |
  | S10 a c0118 promoted spec outside the list weakened (`page.spec`) | 0 | see F2 |
- **Repository safety**: overrides.sh writes only `z-nile/.cache/c0121-ac7.*` (a `git init` fixture, removed by its trap); against the real repository it runs `ls-remote`, `cat-file`, `merge-base`, `show`. check.sh adds only an `echo` of `git ls-remote --get-url origin` outside `check`. No path to the real repository.
- **Mutants spot-run** on the replayed branch (`mut.sh`): N34 (the `--serve` guard exception removed) → cli.spec 7 passed, 1 failed; N33 (main-checkout test off) → 7/1; N23 (worktree spend off) → server.spec 20/1. The carried code still kills them.
- **Scope**: `./zn capture c0121` (4c2b7474): title and Problem unchanged by the re-prep (`git diff 3993dca2 3c956fb3` touches no Problem line).
- **Other items on the judged file**: `git grep -nE 'c0118/docs|c0121, planned' origin/main -- '*/.tracker/issues/*' '*/.tracker/rafts/*' | grep -v /done/ | grep -v /c0121/` → nothing, so no open item can make AC7 red, and c0121 is `solo: true`.

### F1 [medium] The conflict rule names only some of c0121's own hunks, and "a conflict in any other hunk stops the step" stops on the very conflict the prototype resolved; a realistic main conflicts there
Where: c0121.md:328 (Conflict rule: "the `--serve` flag and usage line in `main.luau`; `board.luau`'s `Facts.worktreeSpend`, `Model.live` (type `Live`), `statsHtml` and the `follows` read; … A conflict in any other hunk stops the step"), against its own example ("the `serveLib` require beside `reapLib`") and c0121.md:367.
Evidence: the carried diff's hunks (`git diff 3993dca2 fa44f524 -- <the 7 non-spec paths> | grep '^@@'`): main.luau has five, `@@ -20,6` (the `serveLib` require), `@@ -97,6` (usage), `@@ -791,6` (the `--serve` flag), `@@ -5633,7 +5636,42` (`serveBoard` and its call from `cmd.board`), `@@ -5998,7` (the `READ_ONLY` exception); board.luau has seven, among them `@@ -824,6` (`registryRoot`) and `@@ -1030,6 +1049,22` (the worktree-spend loop); board.html six. The rule names two of main.luau's five, and neither of board.luau's `collect` hunks. The window (`window.sh`): origin/main merged with `proto-c0265-raft` (d9b64df4, c0265 is in design review), then step 1's apply:
```
Applied patch to 'z-nile/engine/main.luau' with conflicts.
Applied patch to 'z-nile/skills/zz-rules/SKILL.md' with conflicts.
== z-nile/engine/main.luau
24: <<<<<<< ours
25: local serde = require("@lune/serde")
27: local serveLib = require("./serve")
28: >>>>>>> theirs
== z-nile/skills/zz-rules/SKILL.md
49: <<<<<<< ours
50:    - `./zn beat <id>` (the work heartbeat, Sync and claim), …
52:    - `./zn board --serve [--port N]` (c0121), …
```
The zz-rules conflict is a named hunk; the main.luau one is the unnamed require hunk. Other open work on the same files (`git grep -lE 'engine/main\.luau|zz-rules/SKILL\.md|z-nile/README\.md|tests/lib/cachepaths' origin/main -- 'z-nile/.tracker/issues/*' 'z-nile/.tracker/rafts/*' | grep -v /done/`, design and Touched lines read): active R0061 (c0135: main.luau, zz-rules), R0068 (c0136: main.luau usage, zz-rules; c0138: zz-rules), R0070 (c0194: main.luau, cachepaths); prepared c0123 and c0189 (main.luau usage lines and `cmd.hooks`, zz-rules); c0247, c0264 (preparing) and c0268 (README). Each of them adds requires, usage lines, `READ_ONLY` entries or command-list bullets in main.luau and zz-rules.
Critique: a `git apply -3` conflict is always between one of the carried hunks and main's change, so the rule's real question is how to resolve it, not which hunk it is in. The list makes a correct resolution (keep main's require, add `serveLib`) a stop and an escalation, while the same paragraph offers that resolution as its example. With five rafts in flight on main.luau, a conflict in the require block, the usage block or `READ_ONLY` is likely before c0121 runs.
Consequences: a stop costs a re-prep, the third. An executor who decides the example outranks the list is guessing.
Recommendation: make the allowed set the carried diff itself: "a conflict may only be between a hunk of `git diff 3993dca2 fa44f524 -- <the 7 paths>` and main's change. Resolve it by keeping every line main has and placing c0121's lines beside them. Stop when that resolution would change or drop a line of main's, or when the conflict is in `c0118/docs.spec.luau` (AC7)." Keep the prototype's three resolutions as examples. Then add an "Other items on the same files" bullet, as c0118's step 1 has (design review 015 F1), with the search above and its result: none of these items changes `c0118/docs.spec`, so none can turn AC7 red; they only widen the conflict rule's window; and c0121 stays solo.
Lesson: z-design/design-the-execution-window

### F2 [low] AC7 says "nothing else" of the one file it lists, but a raft that edits any other promoted spec still passes AC7 and AC6
Where: c0121.md:316 (AC7), :327; overrides.sh `FILES=( z-nile/tests/acceptance/c0118/docs.spec.luau )`; z-design SKILL.md:32 ("promoted specs in `tests/acceptance/` are never edited during execution").
Evidence: S10 above. On the implemented branch, `toBe(true)` became `toBe(true or true)` in `z-nile/tests/acceptance/c0118/page.spec.luau` (`git diff --stat` 1 file, 1+ 1−), and `overrides.sh <main>` → rc 0. AC6 runs that spec and still passes, because it was weakened. Code review is the only guard left: zz-review Code mode's sequestration listing covers only `*/.tracker/**/acceptance/**`, not promoted specs.
Critique: AC7 is new in this re-prep and is the place where "the override is the reviewed text and nothing else" becomes a machine check. As written it covers one file. `git grep -lE 'engine/board|board\.html|main\.luau|README|zz-rules/SKILL' -- 'z-nile/tests/acceptance/*.spec.luau' 'z-nile/tests/tooling/*.spec.luau' | wc -l` → 57 promoted and tooling specs name the touched files. An executor who meets a red promoted spec in a conflict resolution can quietly "fix" it.
Consequences: widening the check changes a sequestered script in prep, which is allowed now. The branch's delta from the merge base is the branch's own work, so main's changes never trip it.
Recommendation (a check.sh AC, not a spec: it judges this branch's delta, not a rule for later work): in overrides.sh, after the compare, `git -C "$TOP" diff --name-only "$BASE" HEAD -- '*/tests/acceptance/' 'z-nile/tests/tooling/'` must list nothing but `z-nile/tests/acceptance/c0118/docs.spec.luau` and, after `done`, `z-nile/tests/acceptance/c0121/*`. Add a row for it (F3).
Lesson: z-design/full-enforcement-means-every-clause

### F3 [low] Rules and mutants has no row for AC7, the one new rule of the re-prep
Where: c0121.md:248-305 (the table ends at the docs row); :371 (three scenarios in the log, with no rows).
Evidence: `grep -nE 'AC7|overrides' c0121.md` finds lines 47, 191, 316, 327, 328, 337, 348, 367, 368 and 371, none of them a table row. c0118's AC9 has rows at done/c0118/c0118.md:390-395 (M78, M82, M83 to M85, M88 to M90).
Critique: zz-review item 0: every behavioural rule needs a row. AC7 states five: equal to the base plus the patch, red when HEAD is already in main, red on an unreadable or unknown tip, red when the patch is missing or no longer applies, green when main moved the file elsewhere. None has a mutant recorded.
Consequences: none for the code; the record is incomplete.
Recommendation: add rows with the runs above as their outcomes: an extra line, or the override reverted (S6, S9, rc 1); HEAD in main (S3, rc 1); main moved docs.spec, not merged and merged (S4, rc 0); an unknown tip (rc 1); the patch missing (c0118's M84 form); and F2's row if it is taken.
Lesson: z-design/spec-design-correspondence

### F4 [low] Text the move to main left untrue
Where and evidence (`grep -nE 'six|simulation|All green|waits for' c0121.md check.sh`):
- c0121.md:174: "c0118's six (promoted in the prototype's simulation)" and "All green on the prototype's full gate". c0118's specs are promoted on main, not simulated, and there are seven (`ls z-nile/tests/acceptance/c0118/`: docs, history, metrics, model, page, real, view). The re-prep's gate (c0121.md:370) had one failure, c0117's stall.
- c0121.md:188 and :246: "its six promoted specs run in AC6". AC6 (check.sh:25-29) runs six of seven and leaves out `metrics.spec`, which reads `z-nile/engine/main.luau` (`grep -n readFile z-nile/tests/acceptance/c0118/metrics.spec.luau` → line 107), a file c0121 changes. It also leaves out `c0115/readme.spec`, which reads the README c0121 changes. The full gate runs both; AC6's label and the Regression guard say "c0118's board … stay(s)".
- check.sh:9-10: "(they exist once c0118 is done, which this issue waits for): built from a variable, so the repository-wide check-paths scan does not read them". c0118 is done and the paths exist.
- Unknowns & experiments doesn't say where the re-prep's rounds start. z-design 5.4: "the issue's Unknowns & experiments says which file it starts at" (here, 006).
Critique: a reader or the code reviewer takes "six" and "all green" as the record, and AC6 as c0118's whole board.
Consequences: none for the code.
Recommendation: "c0118's seven promoted specs (on main)", and either add `metrics.spec` (and `c0115/readme.spec`) to AC6 or say why they are left to the full gate. Record the gate as "1 failed (c0117 dispatch-cli stall; alone 25/0)". Drop the check.sh comment's "waits for" clause. Add one line under Unknowns & experiments: "the re-prep's review rounds start at design-review-006".
Lesson: z-design/restated-rules-move-together

### F5 [low] Step 1's c0117 contract check is prose, and read literally it finds writes outside its list
Where: c0121.md:330 ("write `running` as its only live outcome (every other value written to `st.outcome` is terminal: `ok`, `failed`, `tripwire`, `stopped`, `lost`) … Anything else: stop and escalate").
Evidence: `git show origin/main:z-nile/engine/dispatcher.luau | grep -nE 'st\.outcome *=|st\.outcome,'` → 986 `"running"`, 1158 `st.outcome = outcome`, 1179 `…, st.outcome = …, outcome`, 1790 `st.outcome = nil`, 1841 `"tripwire"`, 1917 `"stopped"`, 1923 (`"lost"`), 2028 `"tripwire"`, 2044 `st.outcome, st.detail = nil, nil`, 2093 `"lost"`, 2103 `"tripwire"`. Lines 1790 and 2044 write `nil`, and 1158 and 1179 write a variable (whose values, at 925-1178, are `failed`, `tripwire` and `ok`).
Critique: the claim is true in substance, and the dispatcher is unchanged since the first prep, so this is not a re-litigation of Stop's rule. But an executor told to verify "every other value written is terminal", with "anything else: stop", sees `nil` and a variable and has no command that settles it.
Consequences: a needless escalation, or an executor who skips the check.
Recommendation: give the check as the command above with its expected hit list (the 11 lines by content), and say that `nil` (a run being reset just before 986 marks it `running`) and the variable writes (from `failed|tripwire|ok`) count as "not live".
Lesson: z-design/instructions-runnable-where-they-run

## Lesson candidates (for the lead)
- z-design (design-the-execution-window): a conflict rule for a carried diff that lists "the hunks we own" by name is narrower than `git apply -3`'s own definition, since every conflict is between a carried hunk and main's change. Check: is the allowed set the carried diff's own hunk list (or a resolution rule: keep main's lines, add ours), rather than a hand-typed subset that leaves out hunks the prototype itself resolved?

Verdict: changes
