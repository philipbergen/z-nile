# Review 002: c0152 (design mode)
Inputs: prep `prep-merge-past-tracker-only` a5aa8d2c (c0152.md, check.sh, acceptance/merge-check.spec.luau, acceptance/docs.spec.luau, design-review-001.md, design-refute-001.md, harvest.md); prototype `proto-merge-past-tracker-only` b34e852b (`z-nile/engine/mergecheck.luau`, `main.luau`, zz-rules, `z-nile/tests/lib/cachepaths.luau`); `z-nile/tests/lib/fence.luau`; `z-nile/engine/main.luau` (remap's scratch worktree); `.github/workflows/check.yml`; `gh pr merge --help`; `./zn lessons --when design --full`. Probes ran in a scratch clone of b34e852b (scratchpad `dr-chores-3/c0152`; its origin is the real repository, read only through `ls-remote`/`fetch`).
Dropped from design-review-001: F2, F3, F4, F5, F6

Rulings on refute 001:
- F1: the user's decision ("Run those checks first") is recorded. Its implementation runs two hand-picked stages and leaves out others that read main's new tracker files (F2 below). The throwaway worktree it added trips the repository fence (F1 below).
- F2: fixed. `--match-head-commit` exists (`gh pr merge --help`: "Commit SHA that the pull request head must match"), and docs.spec pins it.
- F3: fixed. The merge-commit case exists.
- F4: answered. The stricter check.sh rule is chosen now, and both landing orders are stated. The move exception that came with it has a decoy hole (F3 below).
- F5: answered for the reads that decide. The cleanup reads are still ignored (folded into F1 below).
- F6: fixed. The full gate was rerun on b34e852b.

### F1 [high] The trial worktree is registered under the checkout's `.cache`, which trips the repository fence of any spec run in that checkout that overlaps it
Where: c0152.md Design rule 2 ("a throwaway detached worktree `.cache/merge-check-<sha>` of the merger's checkout"); prototype `trial`; the zz-rules command table and main-checkout list ("read-only")
Evidence: `fence.snapshot` (`z-nile/tests/lib/fence.luau:328-363`) records "worktrees registered under .cache" of the run's checkout, and `changes` fails the run when the set differs between start and end (`:378`, `:902-910`). The probe in the scratch clone:
```
(./zn merge-check $H &) ; sleep 0.3|0.6|0.9 ; (cd z-nile && lune run tests/run -- tests/probe/slow.spec.luau)
```
All three runs ended
```
  worktrees registered under .cache
    before: …/c0152/.cache/merge-check-a53df5c07ea1
    after:
Stop and report this; do not repair the repository yourself.
```
and merge-check itself said ok each time. AGENTS.md tells every agent to stop when the tripwire fires. So a reviewed tool that runs normally raises the alarm that means "a check changed the repository", and any session gating in the same checkout halts. The repository already has a rule for exactly this. Remap builds its scratch worktree "in a fresh temporary folder, never at a fixed name under .cache: a spec may have swapped a link in there, and git would build (and remove) the worktree through it (R0026 review 001 F2)" (`main.luau:3084-3092`, `mktemp -d` under `$TMPDIR`). The trial instead first runs `git worktree remove --force` on whatever directory sits at its name. The cleanup ignores failures too (`worktree remove`, `prune`), so a failed removal leaves a registration under `.cache` while the verdict says ok, and a killed run (an agent's command timeout) leaves one for good. Two runs in the same second build the same commit (commit-tree's timestamp has one-second resolution), so they use the same path, and one removes the other's live trial. zz-rules lists `merge-check` as read-only, but it writes objects, a worktree registration and a checkout.
Critique: the c0077 `cachepaths.luau` allowance the prototype had to add is the symptom. The design put the trial where the fence looks for leaks. The tempting fix, teaching the fence to ignore `merge-check-*`, weakens a guard (lesson zz-test/narrow-guard-allowances).
Consequences: outside the checkout, the fence's `.cache` watch never sees the trial. The `cachepaths.luau` line and its overlap with c0117/c0118/c0121 go away. An unknown remains: the nested `tests/run` (jail, lock, fence) has to work from a `$TMPDIR` checkout on macOS and Linux. That is an experiment with a fallback.
Recommendation: build the trial in `mktemp -d "$TMPDIR/merge-check.XXXXXX"`, as remap does. Either (a) use `git worktree add --detach` there, a registration zz-rules allows and the `.cache` watch doesn't cover, or (b) better, use no registration at all: `git archive <merged commit> | tar -x` into the temp folder, then `git init` it there and commit as `merge-check@example.invalid`, so the trial is its own repository, as fixtures are (zz-test). Treat a failed removal as a no that names the leftover path. Run E-new: on the real tree, the nested check-paths run from the temp checkout passes, and with a slow spec running in the merger's checkout during the trial the fence stays quiet. Spec cases: after a run, nothing new under the fixture's `.cache` and no `merge-check` worktree; a case that runs merge-check while a fixture spec run is in progress in the same fixture checkout (or a mutant row "trial under the checkout's .cache" with the case that kills it). Drop "read-only" from the zz-rules row and the main-checkout list wording, and say what it writes (objects and a temporary folder) and that it removes the folder.
Lesson: zz-test/narrow-guard-allowances

### F2 [high] "The gate stages that read tracker files" is a hand list of two; others that judge main's new items together with the PR aren't run
Where: Problem's decision line; Design rule 2 ("`./zn audit` and … c0120's `check-paths.spec`"); AC1
Evidence: the search below finds promoted specs that walk the live tree:
```
git grep -liE 'real tree|every unfinished|this checkout.s working tree|reads the real|the real checkout' -- 'z-nile/tests/**/*.luau' 'pickman/tests/**/*.luau'
```
It returns 22 files, among them c0114/classified, c0114/finished, c0043/rounds, c0116/retired, c0116/promote, c0120/check-paths and c0120/gate-homes. Two of them judge main's new items against the PR, and the trial runs neither:
- c0114 `classified.spec` lists every unfinished item's check.sh with `AC_LIST=1` and requires "criteria listed (none run)" (`:365-405`). A PR that changes `ac.sh`, `tests/run` or the `check` function, merged with a capture on main whose check.sh uses the old form, is red only after the merge. c0139's prep check.sh today (it doesn't parse, see c0139 design review 002 F1) is the kind of file this stage catches.
- the same spec errors when "two issues share the slug" (`bySlug`, `:249-255`), and audit has no slug check (`grep -n slug z-nile/engine/audit.luau`: only `no-slug`). A raft PR's emergent item and a main capture with the same slug pass each side and the trial, then fail the gate after the merge.
The trial also skips check-paths when the merged tree lacks the spec (`if fs.isFile(...)`), a vacuous pass (lesson zz-test/no-vacuous-pass) the moment any later item moves c0120's folder. `z-nile/affected` selects nothing for tracker paths (`lune run z-nile/affected -- z-nile/.tracker/issues/c0139/check.sh …` prints nothing), so there's no selector to lean on.
Critique: the decision was option (b) of review 001, whose list (check-paths, finished, audit) came from memory, not a search (lesson zz-review/lists-paste-their-search; that miss is mine to own). The user decided the class: before the skip, run the gate stages that read tracker files. A wrong ok here is what the decision exists to prevent: main red after a merge that skipped CI. The tempting fix, adding classified.spec to the two, repeats the hand list.
Consequences: the trial needs one named list of tracker-reading stages, kept in one place with the search that found it. A missing stage must refuse, not skip. Every new spec that walks live items must join the list, which is a new exhaustive list (lesson zz-rules/exhaustive-lists-name-new-things), and something must catch a walker that isn't on it. Time grows with the list: measured today, the whole trial took 1.55 s at load average 9.9 (so the 3 s claim is honest), and classified.spec's AC_LIST loop adds seconds per item.
Recommendation: put the stages in one list (in `mergecheck` or `z-nile/tests/lib/`), derived from a pasted search (the Design records the command, its hits, and why each hit is excluded or included), at least audit, c0120 check-paths and c0114 classified. A missing stage is a no. A spec pins that every promoted spec matching the search is on the list or in a reasoned exclusion. Cases: a main capture whose check.sh doesn't list (AC_LIST), and one sharing a slug with a PR's new item, each a no; a trial tree without a listed stage is a no. Mutants: "classified dropped", "a missing stage skipped". If the author wants to keep only audit and check-paths, escalate to the user: (a) the searched list (seconds more per merge); (b) the two stages, accepting a red main after some interaction merges, caught by main's push CI. Record the answer in a `Decided with the user` line.
Lesson: zz-review/lists-paste-their-search

### F3 [medium] The check.sh move exception pairs a deletion with any addition of the same blob, so a dropped check.sh passes beside a decoy
Where: Design rule 1 ("a move … deleted with the same blob added in that commit"); prototype `judge` (`added[new]` keyed by blob only)
Evidence: a main commit that deletes `z-nile/.tracker/issues/c0002/check.sh` and adds a new item `c0009/check.sh` with the identical text satisfies `e.status == "D" and added[e.old]`. Both paths are `publish.allowed`, so the commit is skippable tracker state, although the design says "a changed or dropped `check.sh` is a no". Identical check.sh texts are common: every empty draft's stub, and items whose checks only run their own acceptance specs through `$HERE`.
Critique: lesson zz-arch/sequestered-files-judged-per-item ("Can a deletion pair with an unrelated addition elsewhere in the change (a decoy)").
Consequences: keyed by item, a move is `<root>/{issues,rafts}/[active/|done/]<ID>/check.sh` deleted and the same `<ID>`'s check.sh added with the same blob and mode, which is what ready and done make (d24aabc8's raw diff shows exactly that).
Recommendation: pair a deletion with an addition of the same item id (and same blob and mode). Case: delete c0002's check.sh and add c0009's with the same text → no. Mutant: "paired by blob only".
Lesson: zz-arch/sequestered-files-judged-per-item

### F4 [low] The zz-rules command-table row and step 4's parenthesis restate the old rule
Where: prototype zz-rules diff (command table `merge-check` row; step 4 "(every commit `main` gained … is tracker state the publisher allows, `publish.allowed`, and none touches a file this PR changes)")
Evidence: neither text mentions the existing-check.sh rule. The table row also omits the trial, and calls the command "read-only" (F1).
Recommendation: name both rules and the trial in both places, and pin them in docs.spec (lesson z-design/restated-rules-move-together).

Candidate lessons (for the lead):
- zz-arch: a throwaway checkout a tool builds goes in a fresh `mktemp -d` outside the repository (or is its own repository), never under a checkout's `.cache`, because the fence's tripwire watches worktrees registered there and halts every overlapping run; check: does this command register a worktree, and would `fence.snapshot` of any checkout see it?
- z-design: a decision that names a class ("the gate stages that read tracker files") is met by a list found with a pasted search, kept in one place, with a refusal for a member that's missing; check: is the list the output of a search, and what does the check do when a listed stage isn't there?

Verdict: changes
