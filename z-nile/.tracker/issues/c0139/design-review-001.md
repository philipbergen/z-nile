# Review 001: c0139 (design mode)
Inputs: prep `prep-scripts-refuse-conflicts` 72aa339d (c0139.md, check.sh, acceptance/markers.spec.luau, acceptance/conflicts.spec.luau); prototype `proto-scripts-refuse-conflicts` fed84cd8 (`z-nile/engine/conflicts.luau`, `main.luau` dispatch hunk, both c0115 scripts); `./zn capture c0139` (189ed3d9, Problem filled by 0caa30f6); `./zn lessons --when design --full`. Probes and a mutant ran in a scratch clone (scratchpad `dr-chores-1/c0139`).

### F1 [medium] The guard refuses read-only commands that aren't on `READ_ONLY`, which contradicts the Non-goal and Usability text
Where: c0139.md Non-goals, Design "Where" (hook on "every command outside `READ_ONLY`"), Usability
Evidence: `READ_ONLY` in `main.luau` (prototype, around line 5639) is `list audit find members metrics board workstreams promote-check stamp`. The list was built for "may run in git-less sandboxes", not for "only reads". The commands defined in `main.luau` (`grep -nE '^function cmd\.|^cmd\['`) also include `busy`, `capture`, `lessons` (its search and `--uncovered` forms), `check`, `raft-plan`, `prompt` and the bare `status`/`status <id>`, which only read or only run specs. With the hook they all fail mid-merge with "refusing to run while the checkout has unmerged paths". The Non-goal says "Commands that only read … keep working mid-merge", and Usability says "the read-only commands still work". Resolving a conflicted `harvest.md` or item document, the case in the Problem, is exactly when an agent runs `./zn lessons`, `./zn capture <id>` or `./zn status <id>`.
Critique: the hook uses an existing list for a meaning the list doesn't have. The tempting fix is to add those commands to `READ_ONLY`. That would also exempt them from `guardRepoRoot()`, whose purpose is different (that list's comment is "Only commands that read the tracker run in `.git`-less sandboxes on purpose").
Consequences: a second list, the commands that may run over a conflict, is a new exhaustive list. Every new command must be classified (lesson zz-rules/exhaustive-lists-name-new-things), and a writing form of a command that otherwise reads (`status <id> <to>`, `lessons` writing nothing but `check` running specs that clone the tree) has to be decided form by form.
Recommendation: specify a separate set (for example `CONFLICT_OK`) that is `READ_ONLY` plus the read-only commands and forms named above, each listed with its reason, and keep `guardRepoRoot()` on its own list. Decide `check` explicitly. Running specs over a conflicted tree is arguably right to refuse, but say so. Add `conflicts.spec` cases mid-merge: `lessons`, `capture c0001` and `status c0001` succeed, and `status c0001 <to>` is refused. Add a mutant that drops one of them from the set. Correct the Non-goal so it lists the set, not `READ_ONLY`.

### F2 [medium] The committed-conflict check reads the index, so the commit that commits a conflict is not refused
Where: Design rule 2; prototype `conflicts.marked` (`git grep -l` over the working tree, then `markerLine` on `git show :<path>`)
Evidence: probe on the prototype, a fixture repository with `z-nile/skills/x/a.md` committed clean:
- the working copy rewritten to a whole conflict, not staged → `refusal` = `nil`;
- an untracked `b.md` holding a whole conflict → `nil`;
- after `git add -A` → refused, naming `a.md:1` and `b.md:1`.
`./zn commit` stages with `git add -A` (zz-review, "the author's commit uses `git add -A`"). So `./zn commit` with a pasted or half-resolved conflict in the working tree passes the guard and commits the markers. Only the next command refuses. The two views also disagree in the other direction: a file fixed in the working tree but staged with markers is refused, though the commit about to run would carry the fixed copy.
Critique: lesson zz-arch/one-reader-per-format ("git's view is two views"): give the reader the view of what the command's own commit will carry. The writing commands commit the working tree (`add -A`), so the guard should read the working tree, tracked and untracked (not ignored) files.
Consequences: reading the working tree catches an unstaged conflict, and refuses a staged-but-fixed file only if its working copy still has markers, which is right. Untracked files under the roots then count too, including a scratch file someone left with markers. That is the right refusal for `add -A` callers, but read-only callers are unaffected only if F1's set exists.
Recommendation: read candidates with `git ls-files -co --exclude-standard -- <folders>` (or `git grep --untracked`) and `markerLine` on the working file. Add `conflicts.spec` cases: an unstaged whole conflict and an untracked one each refuse `./zn commit`, with nothing committed. Add a mutant that reads the index copy.
Lesson: zz-arch/one-reader-per-format

### F3 [medium] No case seeds a committed conflict under a project root, or in the two scripts, so dropping either passes
Where: conflicts.spec case 3 (a conflict under `z-nile/skills` only), case 2 (scripts run only with unmerged paths); Rules and mutants
Evidence: mutant run on the prototype: removing the `projects.roots(reg)` loop from `conflictFolders()` in `main.luau` → `conflicts.spec` `3 passed, 0 failed`. The scripts' committed-conflict half (their hand-built folder lists, `{ "z-nile/skills", "pickman/skills" }` plus roots) is never run with a committed conflict, so a script that checks only `unmerged` passes AC3. The capture's Problem is about rename-lesson-ids refusing "a file with merge-conflict markers", not only an unmerged tree.
Critique: lesson zz-test/seed-every-enumerated-case. The folder set is roots × skills folders, and the callers are the engine × two scripts. Each needs a case.
Consequences: the scripts build their folder list by hand, a second reader of "which folders" (lesson zz-arch/one-reader-per-format). If `conflicts.refusal` took the registry and derived roots and `skills.folders` itself, all three callers would share one list and the cases would pin it once.
Recommendation: move the folder derivation into `conflicts` (for example `conflicts.folders(reg)`, from `projects.roots` and `skills.folders`), have the engine and both scripts use it, and add cases: a whole conflict in `z-nile/.tracker/issues/c0001/c0001.md` and one in `pickman/.tracker/…` each refuse a writing command, and a committed conflict refuses each script (exit 2) with no unmerged paths. Add Rules rows and mutants for "roots dropped", "pickman's root dropped" and "script checks unmerged only".
Lesson: zz-test/seed-every-enumerated-case

### F4 [medium] One quoted conflict on main stops every writing command in every checkout, and the design gives no gate that stops it landing and no recovery
Where: E3; Regression guard
Evidence: the rule covers every tracked file under the roots and skills folders, including review files, harvests, lessons, item documents and sequestered acceptance specs (`z-nile/.tracker/issues/<id>/acceptance/*.luau` sit under a root). A whole conflict quoted at line starts in any of them refuses `sync`, `land`, `new`, `commit`, `ready`, `stop` and `worktree` everywhere once it reaches main, the main checkout's `./zn sync` included. E3 relies on authors quoting markers indented. Nothing checks that before merge: no gate stage runs a writing command over the real tree, so a PR adding such a quote is green. (Today `git grep -n -I -e '^<<<<<<< ' -e '^>>>>>>> ' origin/main -- .` finds nothing, so the tree is clean.)
Critique: a guard that fails closed is right (lesson zz-arch/guard-no-is-explicit), but this one fails closed for the whole tool from a document line. The design has to make that state unreachable through review, or recoverable. The tempting fix, exempting review or lesson files, reopens the incident's own file (`harvest.md`).
Consequences: a gate check over the same folders, from the same `conflicts` function, turns such a PR red before it lands. The recovery when one lands anyway (a PR made with plain git, since `./zn worktree` and `./zn commit` refuse) must be written where agents read it.
Recommendation: add a gate stage, or an `audit` problem (audit is in `READ_ONLY` and the gate runs it), that reports `conflicts.marked` over the real tree. Add an AC with a spec case: a fixture committing a whole conflict under a root makes the audit report it. State the recovery in the refusal message or the zz-rules skill: resolve with plain git and land by PR. Also specify the fallback when `projects.load` fails in `conflictFolders()`. Today it returns `{}`, and `git grep … --` with no pathspec then searches the whole repository. Say whether that is intended.

### F5 [low] The edits to c0115's finished experiments: say why the finished-files lesson doesn't apply, and run c0115's check on the branch
Where: Design "Where" (c0115's scripts); Implementation steps
Evidence: lesson z-design/finished-overrides-land-before-ready puts edits to a finished item's sequestered files in the prep. These scripts aren't sequestered (the sequestration diff covers `check.sh` and `acceptance/**` only), and they can't land in the prep because they require `@znile/engine/conflicts`, which only execution creates. But c0115's finished AC14 runs them (`done/c0115/check.sh:127-128`), so the branch changes what a finished check executes. The Implementation steps run `./zn check c0139` and the full gate. The gate doesn't run finished items' `check.sh` files, so c0115's own check isn't named.
Critique: an executor reading the lesson may stop, or may move the edit to the prep, where it can't work.
Consequences: none beyond one more check run.
Recommendation: state in the Design that the files are unsequestered experiments that need the new module, so they change in execution, and add `./zn check c0115` (AC14 on the branch) to step 4. Also record the search for other scripts that rewrite tracked files and why each is excluded. For example, `git grep -lE 'fs\.writeFile|sed -i' -- 'scripts/**' '*/.tracker/**/experiments/**' 'z-nile/.tracker/issues/done/c0120/*.luau'` finds c0120's one-off `rewrite-finished.luau`/`delete-criteria.luau` and c0115's `rewrite-finished-sim.sh`. The capture says "every script that rewrites tracked files".
Lesson: zz-review/lists-paste-their-search

### F6 [low] AC2 and AC3 run the same command, so their labels claim separate results
Where: check.sh AC2, AC3
Evidence: both run `lune run tests/run -- "$A/conflicts.spec.luau"`. A failure of the scripts' case turns AC2 red, and a dispatch-guard failure turns AC3 red.
Critique / Consequences: lesson z-design/spec-design-correspondence: a check's label says exactly what its command verifies. None.
Recommendation: split the scripts' case into its own spec file (as markers.spec already is), with its own fixture so it doesn't depend on case 1's state.
Lesson: z-design/spec-design-correspondence

Candidate lessons (for the lead):
- zz-arch: a guard keyed on an existing command list inherits that list's meaning, not the guard's; check: does the list's own comment say the same thing the new guard needs (for example "reads only" versus "may run without git")?
- zz-arch: a refusal that any one tracked document can trigger must also be a gate check, or one landed line stops the whole tool; check: can a PR that triggers this refusal pass CI?

Verdict: changes
