# Review 001: R0032 (design mode)
Inputs: working tree of prep-lobby-beta-publish on 37af3ec (uncommitted prep): R0032.md, R0032/check.sh, R0032/experiments/prototype.patch, c0064.md, c0064/check.sh, c0064/acceptance/*.spec.luau; scripts/deploy-beta.luau, scripts/runtime-test.luau, scripts/lib/opencloud.luau, .github/workflows/check.yml, lobby.project.json, default.project.json, SETUP.md, tests/acceptance/{c0015,c0003,f0061}; f0065 on origin/main and in the prep-game-over-to-lobby worktree (read only).
Spot runs, with the prototype applied and then reverted: the six c0064 specs plus every c0015 and c0003 spec, f0061/lobby-place, f0031/adapter, c0081/skill-doc and c0001/ci-workflow all pass (141 cases, 23 files). `scripts/check.sh --full` passes (1376 cases, 195 files, as E5 says). Override grep: of the promoted specs that name a Touched path or its basename, only c0015/workflow and c0003/pipeline turn red, and both are named. Repository safety: each spec writes only under its own `.cache/c0064-*`, deploy-beta's copies go to the jail's `mktemp -d`, the fakes listen on loopback only, and no check.sh command writes anything. No finding.

### F1 [medium] The "f0065 adds one more attribute row" plan is blocked by c0064's own sequestered spec
Where: c0064.md Design, "f0065 coordination"; R0032.md Order & dependencies; acceptance/plan.spec.luau, cases "without the game place's id..." and "with the game place's id..."
Evidence: plan.spec pins the game target with `toEqual({ ..., attributes = {}, ... })` in both legacy and split mode. f0065 (R0034, prepped in parallel) says "The lobby's place id is configuration on the game place, like the game place's id on the lobby", and its Non-goals hand "configuring their ids" to c0064. The Design says the row is "added by whichever of f0065 or this raft lands second". Two cases:
- f0065 lands first: R0032's executor must add `{ <attr> = start id }` to the game target, and plan.spec's `toEqual` goes red. That means a sequestered spec has to change, so the executor stops and escalates.
- c0064 lands first: plan.spec is promoted to `tests/acceptance/c0064/`. f0065 is a feature, so it needs a separate narrowing chore, `depends_on` and an `Overrides:` line, none of which R0034 knows about.

Either way, until someone does the extra work, the Beta "back to lobby" path has no id in the game place.
Critique: the Design says the coordination costs one row, but the spec makes it cost an override or an escalation. The obvious fix is to drop `attributes` from the game-target comparison. That loses the guard against a mutant that puts `GamePlaceId` on the game place.
Consequences: if the game target's attributes are left open, the spec must still kill "GamePlaceId injected into the game" and "the lobby's id on the lobby". Whoever adds f0065's row must also know whether that row belongs in plan.spec or in f0065's own spec.
Recommendation: in plan.spec, compare the game target field by field. Use `toEqual` for every field except `attributes`, and for `attributes` assert only `attributes.GamePlaceId == nil`, with a comment that f0065 adds the lobby's id here. Keep the lobby target's `attributes` exactly `{ GamePlaceId = <id> }`. Say in the Design and in R0032's Order & dependencies that f0065's row needs no change to c0064's specs: f0065 pins its own attribute in its own spec on `Beta.plan`. Also say it in R0034, or tell its author. If the lobby id is meant to be part of this raft instead, the user has to choose the attribute name now, and plan.spec then pins it.

### F2 [medium] The lobby runtime script's checks for no game server, `CharacterAutoLoads` and `StartGame` can be deleted without any spec failing
Where: Rules and mutants, row "The lobby structure script fails without GamePlaceId, without a remote or Main, and in the game place"; prototype `tests/runtime/lobby/structure.luau`; runtime.spec.luau
Evidence: each mutant below was applied to the prototype's script on its own, and `lune run tests/run -- tracker/issues/c0064/acceptance/runtime.spec.luau` still gave **12 passed, 0 failed** every time:
- removed the `sss:FindFirstChild("Server") == nil` assert;
- removed the `CharacterAutoLoads == false` assert;
- changed the remote list `{ "StartGame", "Status" }` to `{ "Status" }`.

"Fails in the game place" never reaches the `Server` check, because `ServerScriptService.Lobby` is missing first. No case changes `StartGame` or `CharacterAutoLoads`. The Design lists all of these as what the script checks, and AC4 says the lobby's scripts "pass only in the lobby the deploy builds". These are the checks that would catch the game build published to the lobby, which is the real risk of a two-target deploy (for example, swapped `project` fields).
Critique: E6 says "26 mutants, all killed", but the rules table leaves these out, so a check that no spec exercises was marked as verified. Adding one case per mutant is the obvious fix. A copy of the lobby place with a `Server` folder added still has `Lobby`, so that case would actually reach the check.
Consequences: each case builds the published lobby once more (about 0.1 s). Changing the `CharacterAutoLoads` property on a deserialized place has to work under `@lune/roblox`. It does, since the spec already changes `Parent` the same way.
Recommendation: in runtime.spec, add three cases on a fresh `build(work/lobby.project.json)`. (a) Parent a `Folder` named `Server` under ServerScriptService: the check fails. (b) Set `Players.CharacterAutoLoads = true`: the check fails. (c) Remove `Remotes.StartGame`: the check fails. Add these as rows in the Rules and mutants table, re-run the mutation check, and record the result in E6.

### F3 [low] The "published before the failure" line is never checked
Where: deploy.spec "a refused lobby publish fails, says the game was published..."; Rules table
Evidence: the case asserts only `has(r.stdout, "41")`. The line `published the game place (333): version 41`, printed right after the game publish, already contains `41`. Deleting the `published before the failure: ...` print still passes.
Recommendation: assert `has(r.stdout, "published before the failure: version=41")`. Without that, drop the line from the Design so the docs and the code don't drift apart.

### F4 [low] The Overrides line does not follow the `Overrides:` form
Where: c0064.md Regression guard, line 108: `Overrides (this chore changes them ...):`
Evidence: ticket-prep asks for an `Overrides:` line, and other issues (c0062, c0076, c0078) start the line exactly that way. Anyone grepping for `^Overrides:` misses this one.
Recommendation: start the line `Overrides:` and put the explanation after the colon. The bullet list stays as it is.

Verdict: changes
