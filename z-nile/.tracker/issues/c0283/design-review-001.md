# Review 001: c0283 (design mode)
Inputs: the re-scoped prep in `.worktree/prep-design-approval-gate` (working tree over 9d9faa6e: `c0283.md`, `check.sh`, `acceptance/{approval,approve,dispatch,docs}.spec.luau`, `experiments/mutants.py`, and the staged deletions of the earlier rounds); capture d4692df2 (`./zn capture c0283`); prototype `proto-c0283` f8aa0f04 against `origin/proto-c0263-raft` ba353845 (the mutation copy `proto-c0283-mut` is at 08c0a1a3, with the same engine and texts); origin/main dfa3f8d0 (#295: `engine/approval.luau`, `engine/contract.luau`, `cmd.approve`, the `zn` wrapper); c0263 at `origin/prep-ticket-provenance`; c0261 at `prep-c0261-redesign` 269de5cc and on origin/main; c0250, c0252, c0253 and c0267 on origin/main; c0280, c0282 and c0284 in their prep worktrees. I ran `lune run z-nile/affected` for each Touched path (in the prep tree and on the prototype), and, on the prototype, `ZN_DISPATCH=1 GROK_SESSION_ID=probe CURSOR_AGENT=1 lune run tests/run -- tests/acceptance/c0283/approve.spec.luau tests/tooling/approve.spec.luau` inside this Claude session, so with `CLAUDECODE` and `AI_AGENT` set as well: 9 passed. Both ran through `./zn run`.
Held: I checked these and found no problem:
- The Problem only gained the two 2026-11-12 `Scope decision` lines (I diffed it against the capture).
- The scope table matches #295's code: `approval.refusal` is required in `ready` and checks only drift in `done` and `land`; the wrapper and `cmd.approve` both refuse under `ZN_DISPATCH` and without a terminal; `tracker: approve <id>` is committed with the git identity.
- Nothing the decisions dropped is built: no `status prepared` refusal, no frozen list or its doors, no `--said`. Every outcome the issue keeps has a Behaviour and an AC.
- The sequestered specs are byte copies of the prototype's `tests/acceptance/c0283/`.
- The 23 mutant ids in Rules and mutants match `experiments/mutants.py`.
- The case names in the Overrides exist.
- `main.luau` gains no top-level local.
- The agent check sits after #295's `ZN_DISPATCH` refusal and before `stdinIsTerminal` and `refuseInMainCheckout`, and `--check` skips it.

### F1 [high] c0261, in prep now, rewrites the same `gate`, and its sequestered specs make the dispatcher merge prep PRs. The Design never names it
Where: c0283.md, Other writers of the same paths (lines 72-78); Behaviour 3 (line 60); Regression guard.
Evidence: c0261 is `preparing` on origin/main (4988c034) and "prepared" on `prep-c0261-redesign` (269de5cc). It adds a z-wait branch to `dispatch.luau`'s `gate` (proto-c0261 be21970f), taken when `table.find(f.autoMerge, name)` holds and the PR waits only for checks or for GitHub's merge state. Its sequestered specs pin prep-gate behaviour that c0283 changes:
- `acceptance/dispatch-wait-cli.spec.luau` sets the root `auto_merge = ["prep"]` and asserts, at the prep gate, `realgh pr merge 7 --squash --match-head-commit …` in "waits on z-wait, stores the head, and merges when the PR turned green (AC5)" (line 127).
- The same file asserts `realgh pr merge 10 …` in "a green PR whose merge state is still UNKNOWN waits for `mergeable`, then merges (AC5)" (line 185).
- `acceptance/dispatch-activities.spec.luau` uses the default facts `status = "preparing"`, `autoMerge = { "prep", "raft" }`. Its case "no wait for a draft, a human's merge, a red-free ready PR or the run gate (AC5)" expects `kind == "merge"` for a green prep PR (line 150). Cases at lines 127, 192 and 213, and the PR #8 and #9 cases of `dispatch-wait-cli`, expect a `z-wait` step at the prep gate.

With c0283's `name ~= "prep"`, the three merge assertions go red whatever else happens. If c0283 leaves c0261's wait branch alone, an `auto_merge` that names `prep` (which "keeps accepting `prep` as a name, with no effect") starts a paid model step that waits for CI on a PR the dispatcher will never merge, so "with no effect" is false. If c0283 removes it too, the wait cases go red as well. The design's own search (`auto_merge|prep gate`) matches `c0261.md`, yet c0261 is not in the list. Whichever issue lands second turns the other's specs red: promoted ones are an Override that c0283 does not name, and sequestered ones stop c0261's executor.
Critique: The obvious fix is a line under Other writers saying "the later one merges the two". That doesn't work: c0261's executor may not edit its sequestered specs, and c0283's Overrides cannot name specs that are not yet promoted unless the landing order is fixed.
Consequences: The fix brings three things: a rule for z-wait at the prep gate (this design must say whether a prep PR is waited on at all), a landing order between two rafts, and edits to the other issue's sequestered specs. Those edits can only happen in c0261's prep, which is open now.
Recommendation: put the choice to the user (or to c0261's lead) before either issue is readied, and record it in both documents:
- (a) c0283 adds c0261 to `depends_on` and also leaves `prep` out of the z-wait branch ("the dispatcher waits only at a gate it can merge"). It adds a dispatch.spec case: prep facts, `autoMerge = {"prep"}`, red CI → stop 4 with the reason and the suffix, and no `step=z-wait` in the fake log. It adds the mutant "the prep gate still waits on z-wait", and lists c0261's promoted cases above under Overrides with their narrowed forms.
- (b) Before c0261 is prepared, its prep moves its merge-after-wait cases to the rafting gate and turns its prep-gate wait cases into stops. c0283 then adds the same prep exclusion, case and mutant, and the landing order stays free.

Either way, prove the pair on a prototype that holds both (proto-c0261 merged into proto-c0283) by running both issues' dispatch specs and c0117's. Also name these under Other writers:
- c0256: its four specs set `auto_merge = ["prep"]` in their fixtures but assert no merge. I checked them; they are unaffected.
- c0261's edits to `AGENTS.md`: it rewrites the Subagents paragraph, the line right after c0283's insertion, so the two edits conflict as text.
- c0261's edits to the README and the root `.models.toml`.
Lesson: z-raft/interface-names-every-writer; z-design/run-the-other-rafts-specs; z-design/quote-other-preps-before-promising

### F2 [medium] "The selector prints ALL" is false, and the Overrides were found on 13 grep-chosen files out of a selection of about 229
Where: Affected specs (line 111); E3 (line 118); Regression guard.
Evidence: in the prep tree, `lune run z-nile/affected` prints 225 spec files for `z-nile/engine/main.luau`, 204 for `z-nile/tests/lib/fixture.luau`, 14 for `dispatch.luau` and 13 for `.models.toml` (zz-review: `ALL` is never printed). On the prototype the selector stops with "z-nile/tests/acceptance/c0283/…spec.luau has no watch file", so E3 used a grep instead. That grep covered 8 of the 14 `dispatch.luau`/`.models.toml` specs. It missed `c0117/adapters`, `c0117/ledger`, `c0117/wrapper`, `tooling/openlist`, `tooling/raftcheck` and `tooling/wrapper-guards`, and none of the roughly 200 others that go through the changed `fixture.exec` were run. I read the six it missed and found no prep-merge assertion, and my run of the approve specs under every marker passed. So I know of no missed override; the list is simply unconfirmed. This issue's own earlier round harvested exactly this lesson (its design-review-002 F3).
Critique: The obvious fix is a wider grep. A grep finds the specs that name the edited text, not the ones that depend on a changed harness (`fixture.exec`) or a changed command.
Consequences: The fix costs a run of about 229 files on a loaded machine (c0263's E18 ran the same size in two batches). It also needs a baseline: c0263's E18 recorded 8 cases that are red on main itself, and those must not be read as overrides.
Recommendation:
- Replace the Affected specs paragraph with the selector's real lists, plus the search for the `@znile/engine/provenance` and `@tests/lib/fixture` spellings.
- On the prototype, add a placeholder `tests/acceptance/c0283/watch.txt` that names the engine paths, as c0263's prototype did. `./zn finish` writes the real one.
- Run the union selection there and on `proto-c0263-raft` ba353845, and record both counts in E3.
- Every case that is red only on c0283's tree becomes an Override or a design change.
Lesson: z-design/confirm-overrides-with-a-suite-run

### F3 [medium] The approve-and-merge suffix rides every prep stop, including the ones where the gate holds the PR back because it must not merge
Where: Behaviour 3 (line 60); the prototype's `dispatch.luau` `gate` (`if name == "prep" then why ..= …`); the chain sentence in zz-rules.
Evidence: c0117/control-cli's PR #9, a prep PR carrying `src/x.lua`, now stops with "the prep PR #9 waits for a human: it carries src/x.lua; approve the design with ./zn approve c0091, then merge it yourself and run ./zn dispatch c0091 again". PR #14, which changes another item's documents ("outside the issue's own folder"), gets the same instruction. So do a red PR ("waits for green CI; … then merge it yourself"), a draft and an unmergeable one. The judged refusal exists so that a prep PR carrying code or another item's files waits for a human's judgement (c0117 review 003 F5); the new text tells that human to merge it.
Critique: The obvious fix is to drop the suffix for `carries` only. A red, draft or unmergeable PR has the same problem: its remedy is not "merge it yourself".
Consequences: The suffix becomes a function of the reason, so the zz-rules sentence and its docs needles change with it. c0117's reason assertions match substrings and stay true.
Recommendation:
- Keep `; approve the design with ./zn approve <id>, then merge it yourself and run ./zn dispatch <id> again` for the two stops where nothing else holds the PR: not in `auto_merge`, and the new fallthrough.
- For draft, red and unmergeable, say `; when that is resolved, approve the design with ./zn approve <id>, merge it yourself and run ./zn dispatch <id> again`.
- For a judged refusal, add no approve-and-merge instruction; for example `; a prep PR carries only its issue's folder and skill lessons`.
- Add dispatch.spec cases for a carrying prep PR (the judged reason is kept and "merge it yourself" is absent) and for a red one ("when that is resolved").
- Add the mutant "the suffix ignores the reason" and restate the zz-rules sentence and its docs needle.

### F4 [medium] `fixture.exec` clearing the markers is load-bearing, and has no row, case or mutant
Where: Interfaces (line 70); Existing work (line 92); Rules and mutants.
Evidence: without the scrub, `tooling/approve.spec` and c0283's approve.spec fail in any gate run inside an agent CLI or a dispatched step (`ZN_DISPATCH=1`, which a dispatched z-run's gate inherits). Nothing pins the scrub: on CI, where no marker is set, a `fixture.exec` without the loop still passes every spec. It works today: on the prototype I ran both approve specs with `ZN_DISPATCH=1 GROK_SESSION_ID=probe CURSOR_AGENT=1` plus this session's `CLAUDECODE` and `AI_AGENT`, and all 9 cases passed. E3 records only the run "in this agent session", while the lesson's note from this issue's own first round asks for a run with each variable set.
Critique: The obvious fix is to cite my run. A run proves today's code, not the next edit to `fixture.exec`.
Consequences: The case must set a marker in the spec process itself and then restore it, or the later cases in the same file run as an agent.
Recommendation:
- Add a row "a spec process never inherits the session's markers".
- Give it a case in approve.spec that sets `process.env.ZN_DISPATCH = "1"` and `process.env.CLAUDECODE = "1"` in the spec process, runs a plain approve through `fixture.exec`, expects success, and restores both inside the same case (under `pcall`).
- Add the mutant "fixture.exec does not clear the markers" to the table and to `mutants.py`. That mutant is killed on every host, CI included.
- Record the runs under each marker in E3.
Lesson: zz-test/specs-set-host-markers-explicitly

### F5 [medium] Other documents still describe the dropped design, and c0252 counts on an outcome no issue now delivers
Where: Other writers (lines 72-78); origin/main `z-nile/.tracker/issues/c0252/c0252.md:37,42`; `prep-ticket-provenance` `c0263.md:113`; `prep-provenance-who-from-git` `c0280.md:68`.
Evidence:
- c0252: a line the user confirmed (2026-11-11) says its captured "person-approval gate" is met by #295 "and by c0283", and its Non-goal reads "c0283 (`prepared` refused without it)". The re-scope removes exactly that refusal, yet c0283 names c0252 only in connection with the prep PR.
- c0263 (the layer below, in the same raft) and c0280 say that c0283 adds `approval`, `approvalProblem`, `exemptParse` and `exemptRender` to `provenance.luau` "without changing what is above". In fact c0283 adds `AGENT_VARS` and `approved` and rewrites `hint`'s body.
- c0282's worktree is already updated: its row for c0283 cites the re-scope.
Critique: The obvious fix is to leave this to the raft's coherence review. That review won't see it: c0252 is in another raft. Also, the captured Q2 ("Prepared is refused without it") counts as covered only if the decision's parenthetical is read as the complete list of what stays.
Consequences: The other preps must be told, since their documents are theirs to change, and the user may want the `status prepared` refusal kept somewhere.
Recommendation:
- List c0252, c0263 and c0280 under Other writers with what each now gets, and send the changed names to the c0263 and c0280 preps in this round.
- escalate to the user: either confirm that #295's `ready` refusal is what c0252's Non-goal and the captured Q2 rely on (then c0252's prep rewords line 42), or keep a `status <id> prepared` refusal. If it is kept in c0283, approve must come before `status prepared` in z-design step 5, and issues prepared before it need the old frozen list or its doors; it could also go to a new issue.
Lesson: z-design/quote-other-preps-before-promising

### F6 [medium] The redesign deletes the earlier rounds' records and a harvested lesson, and reuses their ids
Where: the prep worktree's staged deletions (`design-review-001.md`, `design-review-002.md`, `design-refute-001.md`, `harvest.md`, `experiments/proto.patch`, `z-nile/skills/zz-test/lessons/state-files-are-excluded-from-fixtures.md`); the "Review" bullet under Unknowns (line 121).
Evidence:
- `spend.md` rows 2-4 still name `design-review-001`, `design-refute-001` and `design-review-002`.
- The note in `zz-test/specs-set-host-markers-explicitly` cites "c0283 design review 001 F3". After this commit that name points at this review's F3, a different finding.
- `./zn metrics` counts rounds from these files, so two rounds of rework disappear from the stats.
- The deleted lesson says a new tracker-state file must join `engine.STATE`. Any raft can fail that, and the document doesn't mention the deletion.
Critique: The obvious fix is to keep the deletions and explain them in the document. But the user dropped the design and the prototype, not the record of what the earlier rounds cost and taught.
Consequences: if the tooling refuses a second review file of the same kind (zz-review, Output file), the user must decide how the round for a re-scoped design is filed.
Recommendation:
- Restore the two reviews, the refute, `harvest.md` and the lesson, or record a ruling from the user to drop the lesson.
- Ask the user how a re-scope's fresh round sits beside the old rounds. One option: move the old rounds to a `superseded/` folder that `./zn metrics` still counts, and rename this file to match.
- Point the lesson's note at the superseded file.

### F7 [low] "Nothing main keeps writing is touched" is false: the approve row is a second writer of a record that main publishes to
Where: Existing work, "Shared state, guards" (line 93); Behaviour 2.
Evidence: c0263 publishes `confirmed`, `ranked` and `unblocked` rows straight to a backlog issue's `provenance.md` on main, and an issue in prep is a backlog issue. The approve commit appends `approved` to the prep branch's copy. A row published while the prep PR is open therefore meets the branch's row at the end of the file, and GitHub reports a conflict. Since Behaviour 3, the user merges every prep PR by hand, and c0263's union runs only in the engine's merges.
Recommendation: say so in Existing work and in zz-rules' approve row ("if the prep PR conflicts in provenance.md, run ./zn sync in the prep worktree; it unites the records"), and name c0263's union case in the Regression guard. No new code is needed.

### F8 [low] The row's key is `contract=`, while the layer below and every sibling write `design=`
Where: Behaviour 2 (line 57); `approval.spec` "is one row".
Evidence: c0263's record example (`c0263.md:60`) is `approved | human:… | design=1a2b3c4d5e6f; …`. The seeded rows in c0263's provenance and publish specs, c0280's who.spec, c0282's dispatch and provenance specs and c0284's board.spec all use `design=<12 hex>`. Nothing parses the detail, so no spec breaks, but the board and `who` would print the same fact under two spellings.
Recommendation: either write `design=<first 12 hex>` (approval.spec, approve.spec, zz-rules' needle and the mutant patterns follow), or keep `contract=` and say in Other writers that c0263's example and the siblings' seeds change to it.

### F9 [low] Two rules have thinner cases than the rule needs
Where: Rules and mutants rows 3 and 5; approve.spec.
Evidence:
- (a) The dirty-record case writes `| stray`, which the parse check refuses too. The only thing telling the two guards apart is the word "commit", which #295's contract refusal also contains. A dirty check written with `git diff --quiet` misses a staged or untracked record, and it still passes this case.
- (b) "`--check` only reads, so it runs in an agent session" has a case but no mutant row. The missing mutant is "approve: --check is refused in an agent session", made by moving the check above `if not onlyCheck`.
Recommendation: make the dirty input a valid appended row left uncommitted, so that only the dirty guard refuses it; add a variant where that row is staged; pin the guard's own message, `commit {path} first`. Add the `--check` mutant to the table and to `mutants.py`.
Lesson: zz-test/guard-needs-its-own-case

### F10 [low] Labels and claims that say more than the code does, or something different
Where: `acceptance/dispatch.spec.luau:2` ("c0283 AC7") and `acceptance/docs.spec.luau:2` ("c0283 AC4"); Behaviour 1; the prototype's `main.luau` comment above `cmd.approve`; the narrowed Overrides.
Evidence:
- The document maps dispatch.spec to AC4 and docs.spec to AC5, and sequestered headers cannot be fixed during execution.
- Behaviour 1 places the refusal "before its terminal check". But in a session with no terminal, the `zn` wrapper's own `-t 0` test runs first (before Lune) and answers with #295's text, so an agent with no terminal never sees the agent-session refusal.
- "is the one the user accepted" names no ruling; the old design cited zz-rules' "Keep same user, accept detection".
- `cmd.approve`'s comment still says it "commits only that file".
- The narrowed cases keep names that are no longer true: c0117/control-cli's "passes the prep gate … and merges with the real gh itself" and c0117/dispatch's "waits at or passes the prep gate".
Recommendation:
- Fix the two spec headers now.
- State where each refusal answers: the wrapper first when there is no terminal, the engine when there is one.
- Cite the user's ruling.
- Have Implementation step 2 rewrite the comment.
- Rename the two narrowed cases in the Overrides.

### F11 [low] The mutation runner is not run bounded, and an interrupted run leaves a mutant in the copy
Where: Unknowns, line 115 (`python3 experiments/mutants.py "<mutant id>"`); `mutants.py`'s `run`.
Evidence: each spec run inside the runner goes through `./zn run --time 900`, but the outer loop (23 entries, up to 900 s each) does not, which breaks AGENTS.md's Processes rule. If Python is killed between the write and the `finally`, the mutated file stays in `proto-c0283-mut`. The next run then reads mutated text and reports "does not apply" or a false kill.
Recommendation: change the Method to `./zn run --time 3600 -- python3 experiments/mutants.py <ids>`, in batches that fit the limit, and make `mutants.py` refuse to start when `git -C $MUT_WT status --porcelain` is not empty.

Verdict: changes
