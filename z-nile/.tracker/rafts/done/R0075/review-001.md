# Review 001: R0075 (code mode)
Inputs: HEAD 569911680e677a347450871fbd26f6c3d43c2919 (branch R0075-scaffold-arcade-homes), origin/main 74448b59fc7793b28618f761cdf1163e2789b917 (the merge base: the branch holds all of main); `git diff origin/main...HEAD` (125 files); R0075.md and its check.sh; c0184.md, its check.sh and acceptance/ (docs, generic, homes, skills specs); experiments/tooling.patch and experiments/skills/.

Evidence run (all in the worktree):
- `z-nile/check.sh --full`: GATE PASSED (full), 210.5 s. pickman 1811/0, z-nile 1345/0, arcade, portal, snake, invaders and asteroids 21/0 each (3 spec files each).
- `./zn check c0184`: AC1 to AC9 PASS.
- `./zn promote-check R0075`: OK.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing, and `git diff --summary origin/main...HEAD | grep -i 'mode change'` finds nothing.
- Touched modules: every path in `git diff --name-only origin/main...HEAD` is under a Touched module, or is the issue's or raft's own document or spend.
- The ten skills are byte-identical to `experiments/skills/` (`diff`, all five homes).
- Deviation 1 (hand-merged hunks): the pickman-test intro line and zz-test's Spec layout, Gate spec and Hooks sentences are the text `tooling.patch` carries. The c0184 docs.spec (the three zz-test sentences) and check.sh AC7 (the pickman-test sentence) pin each one, so each hand-merged hunk has a spec that fails if it is wrong (zz-execute/run-every-hand-merged-hunk).
- Deviation 2 (truncation): `git grep -nE '(skillsLib|skills)\.(plan|load|inlined|bases)\(' -- '*.luau'` outside c0184's own specs returns main.luau:4187 (`bases((plan((load(".")))), project)`), 4212-4213 (`local found, present = load(".")`, `local list, problems = plan(found)`), 4408 (`inlined((plan((load(".")))), project)`), c0115 skills.spec:28 and :135 (`local list = skills.plan({...})`, a table literal, one value). No other call site passes a multi-value call into a one-parameter function. The fix is correct at runtime and to the type checker. Its recorded cause is wrong (F2).
- Stop hook, failing closed: generic.spec (AC4) runs the real hook on a registry that does not parse, a reader that prints roots only, a third home, an unregistered folder and a tree from before c0114, and all pass. Read: a failed `lune run z-nile/roots -- --projects`, any line with other than three fields, a home that is not `.` or a plain name, and empty output (one empty line, NF=0) each set `gated='[^/]+'`. A grep status above 1 gates the whole list. A registry that does not parse also makes the roots exemption read nothing, so no file is exempted.
- The `.cache` list and the fence scan: `cachepaths.rootsOf` gives `scripts`, `z-nile` and `<home>/scripts` for every project whose home is neither `.` nor `z-nile`. generic.spec pins that list against the live registry. repo-fence's `HOMES` is every registered home except `.` (z-nile's included), plus the root's `scripts/` and `zn`. A registry that fails to load is an error, not a narrower scan. `lune run z-nile/affected -- z-nile/tests/tooling/repo-fence.spec.luau` selects the spec and all six homes' `tests/meta/fence.spec.luau`.
- The search for hand-named pickman paths in live tooling: `git grep -nE '"pickman(/[^"]*)?"' -- scripts z-nile/engine z-nile/lib z-nile/tests/lib z-nile/tests/tooling z-nile/*.luau z-nile/check.sh zn | grep -vE '\-\-project", "pickman"'`. Hits: `z-nile/engine/boundcmd.luau:19` (F1); `main.luau:2451` and `:2478` (c0120's and c0115's frozen move paths, which are history); `skills.luau:408` (the old-name rename map, history); `home.luau:37` (`RULES_HOME`, by design); `z-nile/tests/lib/engine.luau` and `z-nile/tests/tooling/*` (fixtures). The two comment hits in affected.luau and check.sh are examples. `affected.luau`'s HOME_FULL and graph's lobby belong to c0185 and c0188 (Non-goals).

### F1 [medium] The bounded-command seatbelt still names pickman's runner by hand: `lune run snake/tests/run` is refused, `lune run pickman/tests/run` is not
Where: `z-nile/engine/boundcmd.luau:16-23` (`TOOLING`), which R0079 (#227, 71a5d1c4) put on main after c0184's prep, so the Design's search could not see it.
Evidence: piped a Bash tool call through the real hook (`printf '{"tool_name":"Bash","cwd":"<worktree>","tool_input":{"command":"<c>"}}' | ./zn run --time 30 -- lune run z-nile/guard-bash`):
- `lune run pickman/tests/run -- tests/meta`: exit 0.
- `lune run snake/tests/run`: exit 2, "refused by z-nile (unbounded): `lune run snake/tests/run` has no time limit ... Run it as `./zn run --time 60 -- lune run snake/tests/run`".
- `lune run arcade/tests/run -- tests/meta/home.spec.luau`: exit 2, the same refusal.
- `cd snake && lune run tests/run`: exit 0.

`TOOLING` lists `tests/run`, `z-nile/tests/run` and `pickman/tests/run`, and no other home's runner.
Critique: the Problem asks that "every hand-named pickman path in the tooling takes its homes from the registry". This is one more such path, and it treats the five new homes' runner (the same jailed, swept and CPU-limited `z-nile/tests/run`) differently from pickman's. It fails safe (it refuses, it doesn't let anything through), which is why this is medium and not high. The tempting fix is to add the five names to `TOOLING`, which recreates the hand list this chore removes everywhere else. A pattern such as `^[%w_-]+/tests/run$` is the other temptation, and it would let any `foo/tests/run` from any folder through unbounded.
Consequences: `boundcmd` is pure over the command text and a `Context`, so the homes must reach it as data. `guard-bash.luau` would read the registry (`projects.load` at `ZN_CHECKOUT`, or `lune run z-nile/roots -- --projects`) and pass `homes` in the Context. The hook fails open by design (any crash exits 0), so a registry that does not load must keep today's `TOOLING` (pickman and z-nile), never allow every folder. The promoted c0191 `boundcmd.spec` cannot be edited (no override is needed if `TOOLING`'s current entries stay), so the new cases go in a new spec.
Recommendation: handle it in this raft as an emergent issue (zz-execute, emergent issues): `Context.homes` (the registry's homes); `<home>/tests/run` is tooling for each one; with no `homes`, keep today's three entries. Spec cases: with a registry naming `snake`, `lune run snake/tests/run` passes; `lune run elsewhere/tests/run` is refused; with no homes in the Context, `lune run snake/tests/run` is refused and `lune run pickman/tests/run` passes (today's behaviour); end to end through `guard-bash` with a fixture registry naming a third home. If the lead judges this outside the raft, escalate to the user: the options are this raft, a follow-up issue (which leaves the Problem's "every hand-named pickman path" outcome open until it lands), or recording it in c0185's scope.

### F2 [low] The Verification log and commit 33dfcd21 give the wrong cause for Deviation 2
Where: c0184.md, Verification log, "Deviation 2"; the subject of commit 33dfcd21 ("plan now returns two values since R0079").
Evidence: `git log --oneline origin/main -- z-nile/engine/skills.luau` gives only `34950af3 R0049: Skills rename (#120)`. R0079 (71a5d1c4) changed no `.luau` line naming skills. On main, `skills.plan` already returned `out, problems` and `skills.load` returned `found, present`. The type error comes from the prototype patch's own line 130/165 `skillsLib.plan(skillsLib.load("."))`, which passes load's two values into one-parameter `plan`. The inner parentheses (commit cce71e01) are the real fix. The outer ones around `plan(...)` change nothing: a call that is not the last argument is already truncated to one value.
Critique: a future reader of the log, or the harvest, will look for an R0079 interface change that never happened. The real lesson is about the prep: the patch's engine edits never passed the type stage that the Design's E7 and E13 report as passing.
Consequences: none.
Recommendation: correct the log line to say that `skills.load` returns two values (found, present), that the prototype patch passed both to `skills.plan`, and that the gate's type stage caught it on main. Optionally drop the redundant outer parentheses. Harvest it as the candidate lesson below.

### F3 [low] buildLessons' comment still says another project's lessons are left out
Where: `z-nile/engine/main.luau:4181-4182`.
Evidence: the comment reads "Only the lessons of z-nile's skills and of the raft's own project's (c0115): another project's are left out." Line 4190 now also keeps `bases[l.skill]`, the lessons of pickman-arch and pickman-test for an arcade raft.
Critique: the next editor who trusts the comment will "fix" the bases clause away. skills.spec / generic's base-lessons case would catch that, but the comment should not invite it.
Consequences: none.
Recommendation: "... and of the raft's own project's (c0115), with the skills those extend (c0184): any other project's are left out."

### F4 [low] The c0115 docs.spec override reads every entry of each project's skills folder, dotfiles included
Where: `z-nile/tests/acceptance/c0115/docs.spec.luau:188-193` (the c0184 override loop).
Evidence: the loop inserts every name `realfs.readDir(<project>/skills)` returns, then reads `<dir>/SKILL.md`. `skills.load` skips names that start with `.` and anything that is not a folder, but this loop skips neither. Run: `lune` `fs.readDir` on a folder holding `.DS_Store` and `a/` returns both, and `fs.readFile(".../.DS_Store/SKILL.md")` raises "Not a directory (os error 20)". `.DS_Store` is in `.gitignore`, so Finder can leave one in `snake/skills/` unseen, and z-nile's gate then fails on a file git ignores. The hard-coded pickman pair before the override could not hit this.
Critique: the new loop is less tolerant than the reader it should agree with (zz-arch one-reader-per-format).
Consequences: none beyond the spec.
Recommendation: take the names from `skills.plan(skills.load(TOP))` (each skill's `dir`), or skip names that start with `.` and anything that is not a folder, as `skills.load` does. This is a promoted spec the raft already overrides, so the edit keeps the `-- c0184 override:` comment. Then recompute nothing: c0172 pins c0120's docs.spec, not c0115's.

Candidate lessons (reported for the lead; a reviewer writes no lesson file):
- z-design: a prototype patch that edits engine code passes the gate's type stages (Roblox and Lune types over `z-nile/`) on the prototype before the Design reports it passing, because a `--affected` run of one home does not type-check the engine. Check: did the type stage that covers each edited engine file run on the prototype?
- zz-execute: a deviation's recorded cause is checked with `git log` on the file before it names another raft as the cause. Check: does `git log origin/main -- <file>` show the change the log blames?

Verdict: changes
