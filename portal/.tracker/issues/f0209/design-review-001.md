# Review 001: f0209 (design mode)
Inputs: prep worktree `prep-portal-start-place` at 90b00b04de718455f9c3177de3e3db5899dab2bb: `f0209.md`, `check.sh`, `acceptance/{start,deploy,runtime,rollback,docs}.spec.luau`, `experiments/{prototype.patch,c0392-standin.patch,mutants.py,mutants.out}`, `harvest.md`, `z-nile/skills/z-design/lessons/beta-shows-the-last-deployed-merge.md`; the prototype `.worktree/proto2-portal-start-place` at 27e96e92d4c8 (its `portal/experience.json`, `portal/scripts/deploy-beta.luau`, `portal/default.project.json`, `portal/src/server/`, `pickman/tests/runtime/`); c0210 (`c0210.md`, `check.sh`, `acceptance/`) and c0392 as on main 58a574506; f0206 at adb96cb78 and c0202 at f7bc6e2b8 (their prototype patches and acceptance folders); `.github/workflows/deploy.yml`; `./zn capture f0209`.
Run by the reviewer: f0209's five specs on the prototype, 25 passed, 0 failed; c0210's promoted folder on the prototype, 79 passed, 0 failed; `lune run z-nile/affected --` each of the six touched paths, nothing printed; `./zn lessons --check` ok, `./zn lessons --uncovered f0209` ok. Scope: the capture's title, Problem, What should happen and Non-goals are unchanged; the three Guesses are marked pending the user; every captured outcome has a Design and a Checked criterion (AC1, AC2), with Pickman's game over also Observed (OC2). Overrides: the one red promoted spec, `c0210/lobby-start.spec.luau`, is named with c0392 in `depends_on` (c0392's captured wording is being corrected separately, so not judged here).

### F1 [medium] The Observed precondition cannot tell which build a deploy published, and a deploy started before f0209's merge can publish the lobby after it
Where: f0209.md Observed (the preamble: "its log says `published the Portal place (<ROBLOX_BETA_PLACE_ID>)` and names no lobby"); Design §5, row "f0209 merged (every later deploy publishes the portal)"; the third Guess ("from the merge on, every deploy publishes the portal"); `experiments/prototype.patch`, SETUP.md's new bullet ("so from the merge of f0209 every deploy publishes the portal there").
Evidence: on success `deploy-beta` prints only `published the {target.name} place ({target.placeId}): version {result}` (prototype `portal/scripts/deploy-beta.luau:97`). The start place's name is `Portal` whatever its build, and a project is named only when a build fails (lines 64-79). A deploy of `main` without f0209 publishes the lobby and prints the same line, which also "names no lobby": the precondition is met with the lobby at the start place. Second: `deploy.yml` runs on `pull_request` (`opened, synchronize, reopened, ready_for_review`) in the `beta-deploy` group with `cancel-in-progress: false`, and `actions/checkout@v4` checks out the event's merge commit (E1: it fetched `+be045c7…:refs/remotes/pull/514/merge`). A run whose event came before f0209's merge, and which is still pending or running when f0209 merges (the job may take up to 20 minutes), publishes its older merge (the lobby) after the merge. So "every later deploy" is true only of runs whose event came after the merge.
Critique: a tester walks OC1 after "a deploy since", finds the lobby, and checks the log as told. The line is there, so they file a defect against f0209 or retry blindly. The tempting fix, "and the log names the portal", does not work, because the log never names a build.
Consequences: making the deploy print each target's build or project is a change to c0210's `deploy-beta` and to its pinned output cases. That is outside f0209's Touched modules and its capture, so it would be a new issue. The run's own checkout step already holds the proof: "HEAD is now at <m> Merge <head> into <base>".
Recommendation: (1) The Observed preamble names the proof. It is the most recent completed `deploy` run before the walk, whose merge commit `<m>` (from its checkout line) has the switch: `git show <m>:portal/experience.json` shows `"build": "portal"` on the Portal place. This holds for f0209's own run and for any later one, and it fails for a run started before the merge from a pull request without f0209. (2) §5's row, the third Guess and SETUP's bullet say "every deploy whose event comes after the merge". A run queued or still running at the merge publishes its own older merge, and the next deploy corrects it. (3) docs.spec's SETUP case gains a needle for the corrected clause (mutant: the old "from the merge of f0209 every deploy" kept). (4) The new lesson's "How to apply" asks for "the log line that proves which build went out", which this line does not prove. Its body should gain the queued-run case and the checkout-line proof.
Lesson: z-design/beta-shows-the-last-deployed-merge

### F2 [medium] `structure.luau`'s assertions beyond those that tell the portal from the lobby and the game have no case: dropping the PortalPlaceId, PaidPlay, CharacterAutoLoads, Arcade, Lobby or Snapshot check survives every spec
Where: Design §2 (the six bullets), §3 ("proves what no headless spec can: … the publish wrote `PickmanPlaceId` and `PortalPlaceId` on its `ServerScriptService`"); `acceptance/runtime.spec.luau`; Rules and mutants rows F6 and F7.
Evidence: runtime.spec makes three places fail, and each fails at its first difference. The untold portal fails at `PickmanPlaceId`, the first entry of the attribute loop. Pickman's lobby fails at the `Lobby` assertion, or at "ServerScriptService.Server is missing" if that assertion is removed. Pickman's game fails at "Server.Cards is missing". The published portal satisfies everything. A `structure.luau` of only `assert(Server.Cards)` and `PickmanPlaceId >= 1` therefore passes all five cases, and each of these one-line deletions survives:
- the `PortalPlaceId` entry of the attribute loop;
- the `PaidPlay` assertion;
- the `CharacterAutoLoads` assertion;
- each of the two `Arcade` assertions;
- the `Lobby` assertion;
- the `Snapshot` assertion.
F6 removes Cards, Plays, the remotes and Snapshot together, and F7 removes every attribute together, so neither sees a single deletion. This is a plausible mutant nobody listed (zz-review design item 0).
Critique: §3 is why the runtime folder exists: the merge's cicd proves, on a real server, that the publish wrote both ids and that the library is mounted. Step 3 invites the executor to edit the script to main's names. A deletion made then turns nothing red, and cicd proves less than the Design says. The tempting fix is one case per assertion with the module and remote names written in the spec. That pins today's set in a promoted spec, and a portal issue that renames `Plays` would then have to override f0209.
Consequences: names a later issue may rename (`Cards`, `Plays`, the `Play` remote) must stay out of the spec's literals (zz-test/promoted-specs-pin-rules-not-sets). The failures should come from the one `published` place, so no case rebuilds with Rojo.
Recommendation: add one table-driven case to runtime.spec: "the structure check fails, naming what is missing, for each thing the publish or the project gives the start place". On the `published` DataModel, apply one change at a time:
- `PortalPlaceId` unset, and set to 0;
- `PickmanPlaceId` set to 0;
- `PaidPlay` unset;
- `Players.CharacterAutoLoads` set to true;
- `ReplicatedStorage.Arcade`, `ServerStorage.Arcade`, `ServerScriptService.Server` and `ReplicatedStorage.Remotes` each unparented;
- a `Folder` named `Lobby` added to ServerScriptService;
- a `RemoteEvent` named `Snapshot` added to Remotes.

For each one, run `structure.luau`, expect it to fail with a message that names the changed thing, and then restore it (save the attribute, property or `Parent` and set it back). The individual modules and remotes stay covered together by "fails in pickman's game". Add one Rules row per entry (mutant: that assertion deleted) and run them with `mutants.py`.

### F3 [medium] f0209's built-place specs are not selected by the portal changes that would break them, though the Design says a portal issue meets them in its own raft
Where: Maintainability ("a portal issue that renames a server module or a remote updates `structure.luau` in its own raft (AC3's spec pins the place's shape through the built place, not a list)"); `acceptance/deploy.spec.luau` (`children(Server)` equal to `portalServer()`); `acceptance/runtime.spec.luau` ("every script passes in the portal the deploy publishes").
Evidence: the watch that `./zn finish` writes is the layer's changed source files, with documents and skills left out (zz-test, watch). Here that is `portal/experience.json` and `portal/tests/runtime/structure.luau`. deploy.spec and runtime.spec reach `portal/src/server` and `portal/default.project.json` only through Rojo child processes and `fs.readDir`. Selection uses the watch map only (`z-nile/lib/select.luau` header), and a `*.project.json` forces only the static stages (`sel.forces`). A later portal raft can rename the `Plays` module or the `Play` remote, or change `CharacterAutoLoads`. It then passes every `--affected` gate, and its first red is the merge's `--full` gate and the merge's cicd (zz-rules Merging steps 2-3). That comes after its code review, so the merge is BLOCKED until an unreviewed change is made. Separately, deploy.spec's equality maps only `*.luau` files. A folder, or a Rojo `.json`, `.txt` or `.model.json` file under `src/server`, breaks it although the place is right.
Critique: the Maintainability sentence is what the next portal designer will rely on, and it is not true of the gates they run. The tempting fix, a `<stem>.watch.txt` naming the place's inputs, is not available: `./zn finish` is the only writer of watch files, and it writes from the layer's sources.
Consequences: deploy.spec would assert that every name derived from `src/server` is present instead of the exact set. It would then no longer catch an extra child under `Server`. That is not a defect: the lobby's absence is checked on its own (`Lobby` is nil), and so is pickman's game (runtime.spec).
Recommendation:
1. On the prototype, in the promoted layout, write `portal/tests/acceptance/f0209/watch.txt` with the two paths. Run `lune run z-nile/affected -- portal/src/server/Plays.luau portal/default.project.json` and record the result in E3, as the lesson asks.
2. Rewrite Maintainability to say which gates run these specs for a portal change: the full gate at the merge, then cicd.
3. Add the rule to portal-test's new bullet: "a change that renames a module, a remote or a `Players` property that `tests/runtime/structure.luau` names updates it in the same change; only the full gate selects f0209's specs for it". Pin it with one more needle in docs.spec's portal-test case.
4. Make deploy.spec's `Server` check membership plus `Lobby` nil, or count `fs.isDir` entries as children (zz-test/promoted-specs-pin-rules-not-sets).

Lesson: zz-test/specs-read-sources-through-the-selector

### F4 [low] The reasoned row "the switch changes exactly one line" names a mutant its case cannot see; the case is close to a tautology
Where: Rules and mutants, row "the switch changes exactly one line | rollback :: the switch is one line… | the output renamed on the same edit (two lines differ) | reasoned"; `acceptance/rollback.spec.luau`, first case.
Evidence: the Portal place's name, env, build and output are all on one line of `experience.json`. The case compares the manifest with a copy of itself in which the one `"build": "portal"` is replaced. That copy differs in exactly one line for any manifest that holds the string once, a renamed output included, because `rolledBack` replaces within the same text. The case fails only when the Portal place is split across lines. The rename is killed elsewhere: by F5 in deploy.spec and by start.spec's `lobby_version` check.
Critique: a reasoned row whose reason is false lets a mutant go unkilled on the author's word.
Consequences: none.
Recommendation: restate the row as what the case pins: the Portal place's build sits on its one line, and the way back is that one value. Name deploy.spec and start.spec as the killers of the rename. Or fold the row into the second case's (F10), which does the real work.
Lesson: z-design/reasoned-rows-claim-testable-reasons

### F5 [low] Reading `ServerStorage` inside a real Luau Execution task is assumed, not proven
Where: Design §2 (`ServerStorage.Arcade`); Unknowns & experiments (E5 proves only the headless twin).
Evidence: pickman's runtime scripts (`pickman/tests/runtime/structure.luau` and `lobby/structure.luau`) read only ServerScriptService, ReplicatedStorage and Players. Nothing in the repository has read ServerStorage from an Open Cloud task. `structure.luau` is the first script to do it.
Critique: if a task cannot see it, f0209's own merge cicd goes red, and so does every later game merge's cicd.
Consequences: none beyond the fallback.
Recommendation: list it as an unknown with a pass/fail question: in a task on the CICD start place, does `game:GetService("ServerStorage"):FindFirstChild("Arcade")` answer? Either quote Roblox's Luau Execution documentation on which services a task reaches, or leave it to the first cicd. In both cases write the fallback into step 3: drop that one assertion and keep `ReplicatedStorage.Arcade`.

### F6 [low] The record does not match what ran: Affected specs, E3's base and the F17 row
Where: Affected specs; E3; Rules and mutants row F17 ("run (by hand)", "(E3: 24/24 with three variables exported)").
Evidence:
- (a) Affected specs leaves out the touched `pickman/.tracker/game-design.md` and the specs that read it as text (`git grep -lF game-design.md` in `tests/acceptance`): pickman's f0054, f0109 and f0125 `docs` and f0146 `place`, and z-nile's c0053 `publish`, c0120 `docs` and `layout`, and c0183 `designs`. It also leaves out several specs that read pickman-test: c0115 `layout` and `skills`, d0124 and f0110 `adapters`, f0126 `controls` and `views`, f0146 `controls`, and c0259 `readme`. E3's full gates ran all of them green.
- (b) E3's prototype holds neither f0206 nor c0202, both direct `depends_on`, nor c0202's chain (f0145, f0186, f0148, c0380), and E3 does not say so. I read their prototypes. f0206 adds `Remotes.Boards` and `src/server/BoardRelay.luau`, and c0202 changes `pickman/lobby.project.json` and pickman's server. None of that breaks f0209's specs: deploy.spec derives `Server`'s children, `structure.luau` names no `Boards`, and the lobby still fails at `Lobby`. Their sequestered specs read game-design.md for phrases that the appended sentence leaves in place. The design should state this.
- (c) `mutants.out` shows that the runner killed F17, and E3 records 25 passed, not 24.

Critique: a later recut or review relies on these lists to know what the prototype proved.
Consequences: none.
Recommendation: add the missing path and specs to Affected specs, add one E3 sentence that names the absent dependencies and why the specs hold with them, and correct the F17 row.

### F7 [low] The rollback names too few of f0209's specs, and SETUP's rollback bullet says nothing of them
Where: Design §7 ("f0209's start, deploy and runtime specs pin the portal at the start place, the fix's chore narrows or removes them"); `experiments/prototype.patch`, SETUP.md "Rolling the start place back".
Evidence: with the line set back, `rollback.spec` is red too: `rolledBack` asserts exactly one `"build": "portal"` and finds none, so both of its cases fail. `docs.spec` turns red as soon as the fix corrects SETUP ("**The start place is the portal** (f0209)" and the rest of its needles). So the rollback's chore covers all five of f0209's promoted files, not three. SETUP's bullet says only "a tracked fix whose pull request changes that one line back", which tells an operator in a hurry nothing about the gate.
Critique: the rollback's own Override check would find them, but the design and the runbook promise less work than the gate will demand.
Consequences: none.
Recommendation: §7 names all five files (`portal/tests/acceptance/f0209/{start,deploy,runtime,rollback,docs}.spec.luau`) as the rollback chore's Overrides. SETUP's bullet adds one clause saying that the fix's chore narrows or removes f0209's promoted specs, with one docs.spec needle for it.

Verdict: changes
