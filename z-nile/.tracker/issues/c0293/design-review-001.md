# Review 001: c0293 (design mode)
Inputs: prep worktree `prep-agents-md-pipeline-only` at 95dacdfc (origin/main as fetched), with c0293's uncommitted `c0293.md`, `check.sh`, `acceptance/{root,homes,setup,restated}.spec.luau`, `prototype.patch` and `experiments/E3-mutants.sh`; the prototype branch `proto-c0293` at 8fb9070b, run in a scratch clone under the main checkout's `.cache/` (its specs and `check.sh` are identical to the prep's). Peers read: c0136, c0194 (active), c0112, c0181, c0075, c0083, c0189, c0192, c0261, c0141 (backlog), and the in-flight preps in `git worktree list` (c0283's `prep-design-approval-gate`, c0263, c0265, c0274, c0276, c0280, c0282).
Runs: `./zn promote-check c0293` OK. `./zn check c0293` on the prototype: AC1 to AC6 pass, AC7 fails only on the four specs that land first (E2 confirmed). The whole z-nile suite on the prototype: 1749 passed, 5 failed, 255 files. Two of those failures come from c0293 (F1, F2). The other three don't: c0049/parallel-runner and c0165/gate-whole fail on the untouched prep worktree too, and c0165/digest fails only in a clone. Every home's `tests/meta/home.spec.luau` passes on the prototype. M4 spot-run: killed with `ZN_C0293_CARRY=1`, green without it, so the variable does reach the spec.

### F1 [high] AC7 names four promoted specs that don't exist yet as literal paths, which turns c0120's promoted check-paths spec red on main as soon as the prep lands
Where: `check.sh:31` (AC7); `c0293.md` Touched modules.
Evidence: in this prep worktree, `cd z-nile && lune run tests/run -- tests/acceptance/c0120/check-paths.spec.luau` fails `every unfinished item's check.sh, in every project root, names only paths that exist from its home` with `z-nile/.tracker/issues/c0293/check.sh: tests/acceptance/c0112/docs.spec.luau (from z-nile)`, and the same for c0136, c0181 and c0194. The Touched-modules exemption doesn't save it. The scan compares the home-relative word (`tests/acceptance/c0112/…`) with the Touched entries as written (`z-nile/tests/acceptance/c0112/…`), and c0194's spec isn't a Touched path at all. The prep PR changes only tracker files, which select no spec, so its affected gate is green and the next full gate goes red on someone else's PR.
Critique: zz-test, Acceptance checks: "A path a `depends_on` item will create, and is not done yet, is named through `$ZN_ROOT` or created inside `check`." The obvious fix is to add home-relative Touched entries. That makes the scan pass, but it's wrong: c0293 doesn't create those files (c0194's least of all), and c0141 (R0062) is about to change how Touched paths are matched.
Consequences: a path through `$ZN_ROOT` is absolute. `tests/run` takes absolute paths (AC1 to AC5 already pass `$A/…`, and c0193's check.sh passes `"$ZN_ROOT/z-nile/tests/meta/…"`). Until the dependencies are done, AC7 then fails with "could not load", which is the intended red. A list computed at check time would also pick up readers that land later (c0283's and c0261's docs specs, F3).
Recommendation: build AC7's spec list inside a check function. Either name the four as `"$ZN_ROOT/z-nile/tests/acceptance/<id>/docs.spec.luau"`, or (better) take `git -C "$ZN_ROOT" grep -lF AGENTS.md -- '*/tests/acceptance/*.spec.luau'` and fail if any of the 15 specs named in the Test plan is missing from it, so "found nothing" is never a pass. Run `c0120/check-paths.spec.luau` on the prep and record the result under Unknowns.

### F2 [high] c0172's promoted `narrowed.spec` pins `c0120/docs.spec.luau` by digest; c0293's c0120 Override turns it red, and it is neither on the Overrides line nor in AC6's allow-list
Where: Regression guard (`Overrides:`); `check.sh:19` (`OVERRIDES`); Unknowns E2.
Evidence: in the whole z-nile suite on the prototype, `FAIL tests/acceptance/c0172/narrowed.spec.luau :: each narrowed spec is exactly the narrowed text … expected "b7292c46…", got "a7d2899f…"` (the row for `c0120/docs.spec.luau`). On the prep worktree's base it passes. `lune run z-nile/affected -- z-nile/tests/acceptance/c0120/docs.spec.luau` selects only that file, so neither the raft's affected gate nor `done`'s shows it. It shows up at the clean-clone full gate (F7) or a later one. c0239 met the same pin. Its `narrow.py` says "c0172's narrowed.spec changes by exactly one digest, the one of c0120/docs.spec.luau as it is on HEAD (the algorithm is rehash.py's)."
Critique: as designed, the executor can't finish. AC7 requires the c0120 Override, and AC6 forbids touching c0172's spec, so the raft ends in an escalation at the merge. E2 ran only the 15 specs that read AGENTS.md, not every home's suite. A grep for "AGENTS.md" can't find a spec that pins a file's digest.
Consequences: the new digest depends on the Override's exact text, so it can only be computed once that text is final. F5's byte-exact Override check would fix that text in prep, and then the digest can be written into the Design.
Recommendation: name `z-nile/tests/acceptance/c0172/narrowed.spec.luau` on the Overrides line: its `c0120/docs.spec.luau` row takes the overridden file's digest, computed as c0239's `rehash.py` computes it, and nothing else in it changes. Add it to `OVERRIDES` and to AC7's list. Run every home's whole suite on the prototype once and record it in E2 (with the three failures above that don't come from c0293, and why).
Lesson: z-design/confirm-overrides-with-a-suite-run

### F3 [high] c0283, mid-prep, adds a new root paragraph, `**Design approval:**`, which c0293 neither keeps nor drops; Existing work doesn't name it, and either landing order fails
Where: Design, Existing work on the day it lands; `root.spec.luau` `KEPT` and `DROPS`.
Evidence: `.worktree/prep-design-approval-gate` (pushed as `origin/prep-design-approval-gate`, two design reviews already written) has `c0283/acceptance/docs.spec.luau` asserting `lacks("AGENTS.md", { "**Design approval:**", "never try to" })).toEqual({})`. `proto-c0283`'s AGENTS.md hunk adds "**Design approval:** a human approves every design with `./zn approve <id>` … Tell the user to run it; never try to (zz-rules skill, Design approval)." between the Non-negotiable and Subagents paragraphs.
- If c0283 lands first, c0293's AC2 stops on "a base paragraph c0293 neither keeps nor drops (escalate)".
- If c0293 lands first, c0283's raft has to add a paragraph that c0293's promoted `root.spec` rejects ("paragraph 6 is neither the pipeline part nor a shared rule"). c0283's affected gate never selects `root.spec` (F8), so it merges green and main is red at the next full gate.

A second, weaker case: c0261 (prepared) pins "A lead you start by hand runs on the model `.models.toml` names for its activity" in AGENTS.md, and its documents never say which paragraph that sentence goes in. The Design's "c0261 edit[s] the kept paragraphs" is an assumption, not something c0261 states.
Critique: a chore that brings in a rule ("the root holds these paragraphs and no others") has to say how in-flight work gets through it. The obvious fix is to add c0283 to `depends_on` and let AC2's escalation decide. That still leaves the c0293-first order red, and it hands the user the decision mid-raft.
Consequences: wherever the rule goes, the two sequestered specs (c0283 pins exact words, c0293 pins the set of paragraphs) must agree before either one lands. A new kept lead also has to join `homes.spec`'s `ROOT_ONLY` (F10).
Recommendation: escalate to the user, together with c0283's prep, the question of where the design-approval rule lives. Options:
- (a) A fifth kept lead, `**Design approval:**`, in `KEPT` but not among the required ones, so both orders work: `carry` keeps it byte for byte and `shape` accepts it. Cost: one more shared paragraph in a root the user wants to be about engagement only, though this one is about how a z-design ends.
- (b) Treat it as z-design's engagement: c0293's z-design "Engage it" cell (or the map sentence) carries it, and c0283's `docs.spec` pins that wording. Cost: c0283's prep changes its pin, and c0293's `TABLE` changes.
- (c) c0293 adds c0283 to `depends_on` and places its paragraph after a ruling. Cost: c0293 waits for one more raft.

Whichever option is chosen, add a synthetic `carry` and `shape` case with a Design-approval paragraph in the base. For c0261, quote its documents or get its author to name the paragraph (Subagents, as its absence of "which the skills pin to Opus 5.5" suggests). Then add c0283 and c0261 to Existing work, each with its path.
Lesson: z-design/new-rules-migrate-existing-work, z-design/peers-scans-run-on-the-prototype, z-design/quote-other-preps-before-promising

### F4 [high] `experiments/E3-mutants.sh` mutates, commits and hard-resets whatever checkout it is run from
Where: `experiments/E3-mutants.sh:5-7` and `:37-40`; Unknowns E3.
Evidence: the script sets `P="$(pwd -P)"`. `restore()` runs `git -C "$P" checkout -q -- .` and `git -C "$P" clean -qfd -- pickman arcade portal snake invaders asteroids`. M13 runs `git -C "$P" commit -qam "mutant M13 (local)"`, then `git -C "$P" reset -q --hard HEAD~1`, under `set -uo pipefail` with no `-e`. The header says "Run from the prototype worktree's top", and the prototype is `.worktree/proto-c0293`. That is a git worktree sharing refs with the real repository, so M13's commit and reset moved the real `refs/heads/proto-c0293`.
Anyone who spot-runs a `run` row from the raft worktree loses their uncommitted work (zz-review invites spot-runs in design mode, and the code reviewer may do the same):
- `restore` throws away uncommitted changes and cleans six homes.
- `commit -am` sweeps every modified tracked file into the mutant commit, and the reset deletes them.
- If the commit fails (a hook refuses it, or there is nothing to commit), `reset --hard HEAD~1` drops the branch's real last commit.

It also depends on a branch that exists only on this machine, and Unknowns doesn't record that it ran under `./zn run`.
Critique: this breaks zz-review item 9 (every command that changes anything runs in a repository of its own, committing as `@example.invalid`) and item 12. The obvious fix is a guard that refuses unless the folder is a standalone clone. The lesson says why that fails: the main checkout passes the same test.
Consequences: a self-contained script needs the base (27347a8b) and `prototype.patch`, which also makes the prototype reproducible from committed files. M13's AC6 run needs `origin/main` set inside the scratch clone, with `update-ref` there only.
Recommendation: rewrite the script as the lesson says:
- It takes no directory argument.
- It makes a fresh `mktemp -d` (through `./zn tmp new` once c0194 lands), clones 27347a8b into it, applies `prototype.patch` and copies the issue folder.
- It commits there as `c0293-mutants@example.invalid`, with `set -e` around each mutant's setup.
- It removes the folder by a validated path when it exits.

Run it as `./zn run --time 900 -- bash <path>/E3-mutants.sh`, then rerun the 13 mutants and record the result in E3.
Lesson: z-design/prep-experiments-run-in-standalone-clones

### F5 [medium] Nothing checks that each Override is "the base with only the substitution named"; an Override that guts a spec passes AC6 and AC7
Where: Regression guard (`Overrides:`); `check.sh` AC6 and AC7; Rules and mutants.
Evidence: mutant: delete the whole case "AGENTS.md lists every skill by its real path…" from `c0115/docs.spec.luau`, or every `agents` line of c0184's AC7, or c0136's whole docs case. AC6 accepts any edit to a listed file, and AC7 runs what's left, which passes. No Rules-and-mutants row covers how far an Override may go. c0239 (done) had the same shape and checked it in AC8 with `narrow.py` ("deleting an assertion, adding one, or editing a comment is red").
Critique: the Overrides line promises the smallest narrowing, and today only the code reviewer's reading holds the executor to it. The obvious fix is to count `it(` cases, but that misses a weakened assertion.
Consequences:
- The five Overrides known today have fixed text (`prototype.patch`), so each can be pinned byte for byte against the merge base.
- c0136's, c0112's and c0181's base texts don't exist yet, so only a rule can pin them: every removed line names `AGENTS.md` or the local variable bound to it, and every `it(` title survives except a case whose every read was the root file.
- With F2, c0172's spec changes by exactly one digest.

Recommendation: add a Checked criterion (or extend AC6) on c0239's `narrow.py` pattern:
- For each of the five, the base with its substitutions applied equals HEAD byte for byte. Find the substitutions by `grep -c` over the base and assert the counts.
- For the three later Overrides, the removed-line rule above.
- c0172's change is that one digest and nothing else.

Rows: "the c0115 Override deletes its AGENTS.md case" and "the c0136 Override also removes a zz-rules pin".
Lesson: z-design/narrowing-substitutions-found-by-search

### F6 [medium] AC6 judges the whole raft branch, so a raft mate's own Override turns it red even when c0293 is right
Where: `check.sh:19-29`.
Evidence: AC6 runs `git diff --name-only origin/main...HEAD`, and any `*/tests/acceptance/` path outside `OVERRIDES` fails it. c0293 is a raftless chore (`size: 170`, not solo), and z-raft folds chores together by default (zz-rules, raft-plan: "defects and chores folded"). If a mate overrides `c0117/docs.spec.luau`, AC6 prints `promoted specs changed: z-nile/tests/acceptance/c0117/docs.spec.luau`. E3's M13 is exactly that edit, used as a mutant.
Critique: the lesson keeps a diff check only together with an allow-list of the issue's own Overrides, and in a folded raft the issue's own list is not enough. Marking c0293 solo would also fix it, but that takes a user decision.
Consequences: reading the mates' Overrides at check time means parsing their `Overrides:` lines (backticked paths) through `./zn members`, inside `check`. A mate that overrides one of c0293's own files (c0115/docs, say) collides with F5's byte-exact check, so the Design has to say which edit applies first.
Recommendation: make AC6's allow-list c0293's Overrides plus the backticked `tests/acceptance` paths on each other member's `Overrides:` line (`"$ZN_ROOT/zn" members <raft>` inside the function, the raft taken from c0293's `raft:`), with a synthetic mate in a spec case. State in the Design that a mate overriding one of c0293's files is a conflict z-raft must not fold, or ask the user for `solo: true`.
Lesson: zz-test/no-change-claims-check-behaviour-not-the-raft-diff

### F7 [medium] Under the merge rules this is a game pull request, so it needs the clean-clone full gate and `lune run scripts/cicd`; the Design doesn't say so, and every later edit to a project's AGENTS.md is one too
Where: Regression guard ("no place's build changes"); Existing work ("The deploy workflow…"); zz-rules Merging, items 2 and 3.
Evidence: zz-rules Merging 2 says: "A pull request that changes only tooling (no path under a game home — `pickman`, `arcade`, `portal`, `snake`, `invaders`, `asteroids` — outside `<home>/.tracker/`) is gated by `z-nile/check.sh --affected`". c0293 adds `pickman/AGENTS.md` and `pickman/CLAUDE.md`, and the same pair in five other homes, so item 3 applies: `../zn run --time 1800 -- lune run scripts/cicd`. That publishes the CICD places and runs both runtime suites, and a missing `~/.config/pickman/cicd.toml` or a held lease stops the merge. An executor of a z-nile chore who reads this Design expects a tooling merge.
Critique: this is an executability and cost problem. A docs-only change pays for a Roblox publish and the runtime suites, now and on every later edit of a project's file (a skill row, a description).
Consequences: if the user accepts it, the executor needs the cicd prerequisites. Leaving these two files out of "a game" instead is a rule change, restated in zz-rules Merging 2, the end of Worktrees item 2 and zz-test's gate tables, each pinned.
Recommendation: put it to the user. Either the Design states that c0293 merges as a game PR and lists the cicd prerequisites in Implementation steps, or every place that states the tooling definition changes it to "outside `<home>/.tracker/`, `<home>/AGENTS.md` and `<home>/CLAUDE.md`", with a spec pinning the new wording.

### F8 [medium] The declared-inputs step is written for the selector that #293 replaced, and "a new paragraph fails root.spec on purpose" only holds in a full gate
Where: Design, The declared inputs; Maintainability; Affected specs; Implementation step 4.
Evidence: `z-nile/lib/context.luau` builds the context with `inputs = {}`. `select.isInput` reads only watch lists, `fingerprint.of` adds only each entry's text, and `watch.isSource` refuses every `*.md`. So rows in `inputs.tsv` change neither which specs are selected nor which results are reused. Editing `inputs.tsv` does select the specs whose watch files name it (the Design counts c0117's, c0118's, c0165's and c0239's suites, `c0269/titles` and nine tooling specs): gate time for nothing. After c0293 lands, `done` writes its specs' `watch.txt` from source files only, with docs, skills and specs left out, so it names no `.md`. A PR that edits only AGENTS.md (c0283's, c0189's, a later skill-row edit) then selects none of `root`, `homes`, `setup` or `restated` in its affected gate. Watch-net skips its suite when no source file changed, and a tooling PR merges on `--affected`.
Critique: the Maintainability argument rests on a guard that no per-PR gate runs, and F3's c0283 is a concrete case where it misses.
Consequences: dropping the rows costs nothing, since no spec pins c0293's rows. Making doc pins run on doc edits would change the selector for every doc spec (c0115, c0120, c0184 and the rest share the gap). That is a chore of its own, and possibly a decision for the user.
Recommendation: remove `z-nile/tests/inputs.tsv` from Touched modules, from step 4 and from "The declared inputs" (including "c0184's docs row becomes `*`"), and correct Affected specs. Rewrite Maintainability to say where the pins actually run: the full gate, and the checks of items that git-grep the readers of AGENTS.md, as c0261's AC12 does. Capture a chore so that a doc-only PR selects the specs that read that doc, or have each peer in Existing work run c0293's promoted specs in its own checks.

### F9 [low] AC2's check-time case compares the file with itself when it can't find the merge base
Where: `root.spec.luau:316-321`.
Evidence: `local base = if b.ok then … else tip`. Without `refs/remotes/origin/main` (an offline or fixture checkout, or a failed fetch), the base is HEAD, and `carry(new, new)` passes, as the spec's own `none(carry(GOOD, GOOD, MAP))` shows. AC6 fails in that case, so the script as a whole is red, but AC2 prints PASS.
Recommendation: fail the case with "cannot find the merge base with origin/main" when `merge-base` fails. Keep comparing the file with itself only when `merge-base` succeeds and returns HEAD (after landing).
Lesson: zz-test/no-vacuous-pass

### F10 [low] homes.spec's `ROOT_ONLY` leaves out c0194's lead, so a project's file can copy the Temporary-trees rule
Where: `homes.spec.luau:50-56`.
Evidence: `ROOT_ONLY` lists Non-negotiable, Subagents, Processes, No check and `| \`z-nile/skills/`. root.spec's `KEPT` has a fourth lead, `**Temporary trees live in \`.cache/.tmp/\``. Mutant: append c0194's paragraph to `snake/AGENTS.md`, and AC3 still passes.
Recommendation: add that lead to `ROOT_ONLY` with a Rules-and-mutants row, and note in both specs' comments that `KEPT` and `ROOT_ONLY` change together (any new kept lead from F3 included).

### F11 [low] z-nile is the only registered project without an AGENTS.md of its own, so the zz-arch and zz-test pointers disappear from every file a session loads
Where: Design, The project files ("every registered project but z-nile"); the map paragraph.
Evidence: the map says "A project's own skills and decisions are in its folder's `AGENTS.md`" and lists six folders. zz-arch ("designing or writing the tooling: `z-nile/` …, `zn`, `scripts/`") and zz-test do for z-nile what `<name>-arch` and `<name>-test` do for each game. After c0293 they appear only in the README's table and the skill descriptions, and Grok and Cursor's `agent` read only AGENTS.md files.
Recommendation: ask the user whether z-nile gets the same two files (its zz-arch and zz-test rows), named in the map in registry order. The capture's Solution counted the `zz-` rows as "neither a stage nor a project's", and "Each its own AGENTS.md" named five projects, so neither settles it. If the answer is yes, `homes.spec` and `mapFor` drop the z-nile exclusion. c0120's finished.spec stays green, since its "stray `z-nile/AGENTS.md`" case accepts a tracked file at that place.

### F12 [low] JC1 could be partly Checked
Where: Acceptance criteria, JC1; `restated.spec.luau`.
Evidence: c0136's, c0112's and c0181's skill-side wording is already fixed by their sequestered checks:
- c0136's `check.sh` ac5 greps every skill for its exact lead-in sentence ("A lesson goes to the step that erred: …").
- c0181's `docs.spec` pins its `BULLET`.
- c0112's `docs.spec` pins its zz-test invariant sentence.

c0136's `check.sh` notes that its exact sentences "run at done and never again", so after it is done no promoted spec pins the lead-in.
Recommendation: add AC5 cases pinning those three skill-side texts, each with a floor on how many skills carry it, and leave JC1 only the clause-by-clause comparison.

Verdict: changes
