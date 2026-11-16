# Review 001: d0297 (design mode)
Inputs: prep worktree `prep-affected-selects-sequestered-specs`, base `de33c578`, with the prep's uncommitted files: `d0297.md`, `check.sh` (`cc31a6ab`), `acceptance/select.spec.luau` (`e9fad216`), `acceptance/cli.spec.luau` (`3bc508d9`), `proofs/finish.spec.luau` (`6396778c`, which matches AC3's pin), `experiments/prototype.patch` (`0a57dc26`), `experiments/mutants.sh`, `experiments/mutants.txt`. Code read: `z-nile/lib/select.luau`, `z-nile/lib/watch.luau`, `z-nile/lib/context.luau`, `z-nile/affected.luau`, `z-nile/specs.luau` (scope), `z-nile/engine/main.luau` (`cmd.finish`), `z-nile/engine/watchcmd.luau` (`capture`), `z-nile/engine/trace.luau` (`isSpecForIssue`), `z-nile/check.sh`, `z-nile/templates/raft/check.sh`, `z-nile/engine/projects.luau`. Other items read: c0180, d0298, c0265, c0248 and d0331. Also read: `./zn capture d0297`, zz-test, zz-execute Phase 1 and 2, and the lessons (`./zn lessons`).
Reviewer runs:
- E1 reproduced on this tree. Also, `lune run z-nile/affected -- --project z-nile` on this very prep branch prints its own `acceptance/cli.spec`, `acceptance/select.spec` and `proofs/finish.spec`.
- The Affected list re-derived: 235 paths, identical to the document's.
- The AC3 proof run in a scratch clone with the patch applied and M10 (finish omits the flag). It fails on its assertion (`finish.spec:184`: results.txt holds only `pickman/tests/unit/alpha.spec.luau`), so E3 and the R11 row hold. Run with `./zn run --time 600`.

Scope fidelity: the title, Problem and capture's outcomes are unchanged. The Solution was only added to, under "(Added in prep)". The new Non-goals drop no captured outcome. Each captured outcome has a Checked criterion: AC1/AC2 (the gate never runs one), AC2 (green on a prep branch: a fair proxy, since the gate's spec stage runs exactly what the selector prints), and the promoted select/cli specs (a spec case pins it).

### F1 [high] AC4 passes without the usage line it names
Where: `check.sh` AC4, `g "--own-acceptance" "$ZN_ROOT/z-nile/affected.luau"`; Design, "The fix", the `z-nile/affected.luau` bullet.
Evidence: AC4 states "z-nile/affected.luau's usage names the flag". Its check is a fixed-string grep that any occurrence in the file satisfies. The prototype has three: the usage line (`--   ... --own-acceptance   -- also the layer's own ...`), the parse branch (`elseif a == "--own-acceptance" then`) and the header sentence. An implementation that parses the flag and writes no usage line passes AC4. No row in `mutants.sh` deletes the usage line. Following the rubric, this is a criterion a wrong implementation passes.
Critique: the tempting fix is to grep for the prototype's whole usage line. That pins the comment's exact wrapping and padding, which the executor may lay out differently.
Consequences: a pin on the header's usage block holds only until `done`, because check.sh is not rerun afterwards. Another item that edits that header during the window (c0180's re-prep touches `z-nile/affected.luau`) must keep the shape, not the wording.
Recommendation: anchor the grep on the usage block's shape, not on the parse code: `grep -qE '^--[[:space:]]+\.\.\. --own-acceptance[[:space:]]' "$ZN_ROOT/z-nile/affected.luau"` (the `--   ... --flag` form every usage line has). Keep the two zz-test greps. Add to `mutants.sh`: a mutant with the usage line deleted, which AC4 must kill, and a correct variant with the usage text reworded after the flag, which must stay green. Record both in E5.

### F2 [medium] The run behind `Overrides: none` is incomplete; its open part can't run where the raft will run; its fallback misfiles four promoted specs; d0298 isn't named
Where: E4, E7, Implementation steps 0 and 5, Regression guard (`Overrides: none`), Siblings.
Evidence:
- **78 slow-tier specs never ran.** "Affected specs" says 97 of the 235 are slow tier. E4 ran 19 of them by name, so 78 never ran on the prototype.
- **The 8 that ran can't be told apart from main.** stack-fix, stack-land, trace-land, watch-map, c0008/done-order, c0067/ready, c0084/commit-phase and c0120/finished are red in the dispatched step. The first four are the specs that drive `./zn finish` and the layer branch. watch-map's 4 failures have no control: E4's main control covers "the same 7 files", and watch-map is not one of them.
- **E7 can't run under dispatch.** E7 and steps 0 and 5 say "outside a dispatched step (an interactive session in the raft's worktree, or the merge's gate)". A raft run by `./zn dispatch` has no such session, because z-run is the headless run step. "The merge's gate" comes after `./zn done`, when "the executor stops and escalates" can no longer keep the change off the PR.
- **The fallback misfiles four specs.** E7 says "(a tooling spec, so a fix in the raft, not an override)". But c0008/done-order, c0067/ready, c0084/commit-phase and c0120/finished are promoted acceptance specs under `z-nile/tests/acceptance/`. A red one is an Override with its chore in `depends_on`, which an executor can't add.
- **d0298 owns these reds and isn't named.** d0298 (prepared, R0096) has a Design section "3. Spec runs drop a dispatched step's environment". There the spec runner unsets `fence.STEP_VARS` and drops `z-nile/bin` from `PATH`, with the outcome "the specs that failed only inside a dispatched step pass there too". That is the cause E4 gives for these reds (the publish broker and the step's git wrapper). Its Problem also names c0008/done-order, and it changes `cmd.ready` and zz-test.
Critique: the tempting fix is to add `depends_on: [d0298]`. That puts d0297 behind R0096, which z-ready refuses until c0266, c0302 and c0304 (three new backlog chores) are done, while every prep PR waits on d0297. The other tempting fix is "run them at the merge's full gate", which comes after `done`.
Consequences: a run "without the step's variables" needs a stated environment and a main control taken in that same environment. The jail and the fence still guard the real repository there. Only the step's variables are removed, which is what d0298 itself does for every spec. If a spec turns red only on the prototype, the design changes now rather than stopping the raft mid-layer.
Recommendation: close E7 in this revision with the lesson's method:
1. Run the 97 slow-tier specs of the Affected list by name on the prototype and on unmodified `main`. Run both without the dispatched step's variables: `env -u` each of d0298's `STEP_VARS` (`ZN_DISPATCH ZN_HEADLESS ZN_DISPATCH_DIR ZN_DISPATCH_HOME ZN_REAL_GIT ZN_REAL_GH ZN_PUBLISH_BROKER ZN_PUBLISH_TOKEN ZN_DISPATCHER_PID ZN_AGENT_GH_TOKEN`), with `PATH` minus `z-nile/bin`, as c0117/control-cli and c0302/layer.sh already do.
2. Record pass and fail per file next to its control.
3. Give steps 0 and 5 that same command, so they can run where z-run runs.

If that environment can't be had in prep, say why in E7 and keep it for Phase 1 with that command. Either way, fix the fallback: a red spec under `tests/acceptance/` means stop and send d0297 back to z-design for an Override; a red spec under `tests/tooling/` is fixed in the raft. Name d0298 in Siblings: it owns the dispatched-step reds, it does not change the selector call or finish's argv (check its prototype), and say which landing order holds.
Lesson: z-design/checks-pass-in-a-dispatched-step; z-design/confirm-overrides-with-a-suite-run

### F3 [medium] The promoted wiring case pins `cmd.finish`'s file, which c0180 is to split out of `main.luau`
Where: `acceptance/cli.spec.luau:153` (`t.expect(holders).toEqual({ "z-nile/engine/main.luau" })`) and `:155` (`string.find(main, "\nfunction cmd.finish(", 1, true)`); Siblings, the c0180 bullet.
Evidence: c0180 is preparing and touches `z-nile/affected.luau` and `main.luau`. It carries the Scope decision (user, 2026-11-01) "split main.luau into one module per command", and its AC1 reads "the engine is split: one module per command, dispatched by literal lazy requires … only `main.luau` and `raft-plan` … require command modules". After that split, finish's selector call lives in a command module. `holders` then names that module, and `main.luau` holds no `\nfunction cmd.finish(`, so the promoted `z-nile/tests/acceptance/d0297/cli.spec.luau` is red on correct code. Because d0297's watch names `main.luau`, c0180's prep will select the spec and must carry it as an Override. The case asserts an exact set (the files that hold the flag) that planned work changes. Siblings mentions c0180 only for its own sequestered specs.
Critique: the tempting fix is to note the collision in Siblings and leave it to c0180's Override. That knowingly creates an override for a planned change.
Consequences: a check that doesn't depend on the file must still kill M10 (finish omits the flag) and M11 (the gate passes it). It must still refuse the flag in any other engine command (the dispatcher, `done`). It must not depend on a naming convention c0180 hasn't settled.
Recommendation: pin the rule, not the file:
- (a) No listed file outside `z-nile/engine/` holds the flag in code.
- (b) In `z-nile/engine/**`, every use of the flag in code lies inside the argv of a `"z-nile/affected"` call, in the one file and function that also writes the layer's `results.txt`, located by that content. Today that is `cmd.finish` in `main.luau`.
- (c) At least one such use exists.

Add to `mutants.sh` a correct variant V5, with finish's body moved into `z-nile/engine/finish.luau` and called from `main.luau`, which must stay green. Add a mutant with the flag added to another engine command's selector argv or the dispatcher, which must be killed. Name c0180's split in Siblings as the change this case is written to survive.
Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F4 [medium] The "no gate passes the flag" guard is not selected when a gate file changes
Where: `acceptance/cli.spec.luau`'s wiring case (R10, M11); Maintainability ("AC2 fails if a gate, a hook or a forwarder ever starts passing the flag"); Regression guard.
Evidence: once promoted, the case is bound by `z-nile/tests/acceptance/d0297/watch.txt`. `./zn finish` writes that file in `watchcmd.capture` as `watch.forSuite(…, watch.sourceOf(<the layer's diff>))`. Here that is `z-nile/affected.luau`, `z-nile/engine/main.luau` and `z-nile/lib/select.luau`. A skill is not a source, and `capture` adds no shared pins; only the backfill does. The case reads `z-nile/check.sh`, `scripts/affected.luau`, `zn`, `z-nile/lib/*.sh`, `z-nile/bin` and `.claude` as text. So M11, the very regression R10 exists for (`z-nile/check.sh` passing `--own-acceptance`), selects no d0297 spec. `lune run z-nile/affected -- z-nile/check.sh` won't list it, and the layer gate, RC0 and the PR's `--affected` stay green. Only a `--full` run catches it.
Critique: the tempting fix is to hand-add `z-nile/check.sh` to the promoted `watch.txt`. That edits a file that finish writes, in a sequestered folder.
Consequences: a tooling spec with its own `<name>.watch.txt` must name only paths that exist (watch-check), and `./zn commit` keeps those paths current on renames. A hook script added later isn't named until someone adds it, but the scan still reads the whole listed tree, so the gap is only in selection.
Recommendation: add to the Test plan an executor-written regression spec, `z-nile/tests/tooling/own-acceptance-callers.spec.luau`, with the same "no gate, hook or forwarder holds the flag in code" scan. Give it an `own-acceptance-callers.watch.txt` naming, sorted, `scripts/affected.luau`, `z-nile/check.sh`, `zn` and the selector-running scripts under `scripts/hooks/` and `z-nile/lib/`. On the prototype, show that `lune run z-nile/affected -- z-nile/check.sh` and `-- scripts/affected.luau` list it, and record that in E4. Alternatively, if the merge's `--full` is accepted as the only net for that half, say so in the Regression guard and in Maintainability.
Lesson: zz-test/specs-read-sources-through-the-selector

### F5 [medium] The pinned AC3 proof drives commands that in-flight items change, and only d0331 is named
Where: `proofs/finish.spec.luau` (pinned by hash in AC3); Siblings; Implementation step 0.
Evidence: the proof builds its own fixture by hand: a registry, issue and raft front matter, check.sh files, `seal.stamp`, and a `gh` stub that answers `pr list` with `1` and `pr view` with `main`. It then drives `ready`, `worktree`, `start` and `finish`, and asserts results.txt byte for byte. The in-flight items that change those commands are:
- d0298 (prepared): changes `cmd.ready`'s approval refusal and `keepRecords`.
- The active heartbeat raft (c0265, c0274 to c0277): c0265's envelope says "a claim path (`status <id> preparing`, `ready`) beats at once and remembers its stamp", and c0277 changes the `./zn worktree` lookup.
- c0248 (prepared): `ready` writes `layers: reviewed`, and `start` waits until the layer below is complete.
- d0331: changes finish's base.

Siblings names only d0331. If any of them lands first and the fixture no longer goes through, AC3 is red on correct code in a file the executor can't edit.
Critique: the tempting fix is "the executor will notice in Phase 2". It will, but only after the raft is claimed, and the result is a stopped raft.
Consequences: an instruction to run the check on the day's `main` needs an expected result for each AC. AC3 is green on `main` by design (it is a regression guard); AC1, AC2 and AC4 are red on assertions.
Recommendation: name each of these items in Siblings, with what the proof needs from it and the landing order that holds. Add to step 0: "before `start`, run `./zn check d0297` on the day's `main`: AC3 green; AC1, AC2 and AC4 red on assertions (E1's lines). A red AC3 there means stop and re-prep: the proof is pinned."
Lesson: z-design/design-the-execution-window; z-design/stubs-inherit-pending-redesigns

### F6 [low] Restated rules still say a layer branch selects the ticket's acceptance specs
Where: the zz-test edit in the Design and the prototype; the header of `z-nile/affected.luau` (lines 11 to 13 and the new sentence); `z-nile/lib/select.luau:23`; the Design's "`sel.scope` calls `sel.affected` without `own`".
Evidence:
- **zz-test contradicts itself.** The prototype's paragraph keeps "…and, on a layer branch, that ticket's acceptance specs when the change includes a source file its watch names", then adds "It never selects a sequestered spec". Before `done`, a ticket's acceptance specs are all sequestered (its promoted folder doesn't exist yet), so the two sentences contradict each other.
- **The header repeats it.** The header of `z-nile/affected.luau` keeps "On a layer branch …, a change that includes a source file selects that ticket's acceptance specs".
- **The `current` comment is stale.** `Context.current` is still described as "the current raft's acceptance specs", though they are now dropped unless `own` names them.
- **"Only the current ticket's" is wrong on old raft branches.** The new header says the flag prints "only the current ticket's". On an old raft branch (`R####-…`), `currentSpecs` returns every member's specs, so the flag adds all of them.
- **The Design misdescribes `sel.scope`.** In the prototype, `sel.scope` passes `ctx` through with `own` unchanged. "Without own" is true today only because `specs.luau scope` builds its context with `context.build`, which sets no `own`.
Critique: an executor who reads zz-test expects `--affected` on their layer branch to run their acceptance specs. They no longer run there.
Consequences: none beyond the text. No promoted spec pins these sentences (searched `*/tests/**` and the sequestered specs for them).
Recommendation:
- Reword the layer clause in zz-test and in the header: "on a layer branch, that ticket's promoted acceptance specs (`tests/acceptance/<id>/`) …; its sequestered ones only with `--own-acceptance` (`./zn finish`)".
- Fix `current`'s comment.
- Say "the current layer's ticket's (every member's on an old raft branch)".
- Either make `sel.scope` call `sel.affected` on a copy whose `own` is nil, with a select.spec assertion that `sel.scope(ctx(nil, { OWN }), { "pickman/.tracker/issues/active/c0010/c0010.md" })` is `"ALL"`, or reword the Design to "scope's callers never set `own`".
Lesson: z-design/restated-rules-move-together

### F7 [low] AC2's layer case doesn't run the form the gate uses on a layer branch
Where: `acceptance/cli.spec.luau`, "AC2: on a layer branch the ticket's own sequestered specs print only with --own-acceptance".
Evidence: on a layer branch, the raft's RC0 runs `z-nile/check.sh --project <p> --affected`, that is `lune run z-nile/affected -- --project pickman` with no explicit paths (the branch against `origin/main`). The layer case calls `affected({ src })` without a project and the two flag forms only. A CLI that sets `own` whenever `--project` is given passes all four cases while the RC0 gate runs the ticket's sequestered specs. The prep-branch case claims "every form the gate uses"; the layer case covers fewer forms.
Critique and Consequences: none beyond the case.
Recommendation: in the layer case, commit a change to `pickman/src/alpha.luau` on `R0010/1/c0010`. Assert that `affected({ "--project", "pickman" })` and `affected({ "--project", "pickman", "--base", "main" })` both return `{}`. Add the mutant "`own` set whenever `--project` is given" to `mutants.sh`; it must be killed.

## Lesson candidates (for the lead to harvest)
- z-design: *a fallback that names specs must classify each by where it lives.* The rule: a spec under `tests/acceptance/` is promoted, so its red is an Override that needs a chore, never "a fix in the raft". The reason: E7 filed c0008, c0067, c0084 and c0120 as tooling specs (F2). The check: for each spec a fallback names, is it under `tests/acceptance/` or `tests/tooling/`, and does the fallback say stop-and-re-prep for the first?
- z-design: *a step that must run "outside a dispatched step" needs the command that makes it runnable inside one.* The rule: give the command (d0298's `STEP_VARS` unset, `PATH` without `z-nile/bin`), or a reason it can't be done. The reason: a raft run by `./zn dispatch` has no other session, and "the merge's gate" is after `done` (F2). The check: can every Phase 1 step and every implementation step run where z-run runs?

Verdict: changes
