# Review 002: R0050 (design mode)
Inputs: working tree on main @ 360511a (uncommitted): `tracker/rafts/R0050/{R0050-game-alias-requires.md,check.sh,design-review-001.md,design-refute-001.md}`, `tracker/issues/c0390/{c0390-game-alias-requires.md,check.sh,acceptance/*.spec.luau}`, `scripts/lib/graph.luau`, `tests/lib/place.luau`, `tests/meta/architecture.spec.luau`, `scripts/affected.luau`, `scripts/check.sh`, `tests/run.luau`, `scripts/tracker/main.luau` (promote-check), c0020 promoted specs, R0040 raft and f0120/f0130 (context), architecture/testing/tracker/review skills, `tracker/architecture.md`.
Dropped from review-001: F1, F2, F3, F4, F5, F6
Method: I built a fresh prototype of the c0390 Design in a scratch worktree (`/tmp/r0050-review2`, since removed): graph about 60 lines, place 6 lines, plus a one-bullet skill edit. Results:
- On unmodified main, c0390 `check.sh` fails AC1 to AC4 (0/4).
- With the prototype, `tracker/rafts/R0050/check.sh` passes 4/4: the full gate, c0390 AC1 to AC4, promote-check and RC1. `lune run tests/run` gives 113 passed. The tree stays clean apart from the gitignored files.
- The acceptance specs pass stylua and selene. They run in the gate, because `tracker/` is in `LUAU_DIRS`.
- R0040 simulation: I added `src/shared/Logic/Session/init.luau` and `src/server/Sessions.luau` requiring `@game/ReplicatedStorage/Shared/Logic/Session`. `tests/meta` and the c0020 place rules pass.

Round-1 answers verified:
- F1: the no-default-roots mutation now fails graph-build.
- F2: the skill phrase and RC1 are in place, and RC1 rejects a crafted `@game/ServerScriptService/...` require.
- F3: string-prefix, fallback, no-exact-root and case-insensitive mutations each fail graph-game.
- F4: the URL and the quote are in E2.
- F5: `Main.server` → nil is asserted.
- F6: RC1 rejects a crafted `require( '@logic/Maze')`.

### F1 [high] AC1 can still be passed by two wrong implementations: roots sorted by path length, and `.client` scripts resolvable
Where: c0390 AC1 ("lists the project's `$path` nodes, longest first ... returns nil for ... script ... specs"); Design `resolveGame` step 4 (".server or .client"); `graph-game.spec.luau:8-22,35-42,81-83`.
Evidence: I mutated the prototype. Each mutant passes graph-game and graph-build 12/12:
- **M-pathsort**: `gameRoots` sorts by `#a.path > #b.path` instead of by instance length. The case "lists every $path node" compares through `rootsMap`, which throws the order away. The fixture's nested path `tests/fixtures/graph/B` also happens to be longer than its parent's `tests/fixtures/graph`, so the nested node still comes first. A project where a nested node maps to a shorter path, for example `Shared = src/shared` with `Shared.Vendor = lib`, would resolve `@game/.../Shared/Vendor/X` to `src/shared/Vendor/X`. That breaks the Design's "the longest mapped node owns its subtree".
- **M-client**: step 4 checks only `%.server$`. No case covers `.client`, because `PROJECT` has no client root. With the real roots, `@game/StarterPlayer/StarterPlayerScripts/Client/Main.client` then resolves to `src/client/Main.client.luau`, and tests/meta records an edge to a LocalScript. This is exactly what review-001 F5 was about, but only its `.server` half is pinned.
Fix: two changes to `graph-game.spec.luau`.
- In "lists every $path node", also assert the order: for each `i > 1`, `#roots[i-1].instance >= #roots[i].instance`. M-pathsort fails this with the current fixture, because the instance lengths come out as 26, 24, 20, 26.
- Add `StarterPlayer = { StarterPlayerScripts = { Client = { ["$path"] = "src/client" } } }` to `PROJECT`, and the matching entry to the expected `rootsMap`. Then assert `@game/StarterPlayer/StarterPlayerScripts/Client/Main.client` → nil and `@game/StarterPlayer/StarterPlayerScripts/Client/Main` → nil.

### F2 [medium] "`@game` only into ReplicatedStorage" is enforced only by one-shot raft checks, so the permanent gate accepts a client require into ServerScriptService
Where: c0390 Design, Architecture skill bullet ("The static checks can't tell these apart, so the raft checks (R0050 RC1, R0040 RC3) grep for them"); R0050 RC1.
Evidence:
- In the prototype I added `src/client/Bad.luau` with `require("@game/ServerScriptService/Server/Sessions")`. `tests/meta/architecture.spec.luau` and `tests/acceptance/c0020/place-rules.spec.luau` both passed (12/12), and so would `scripts/check.sh --full`. Only R0050's RC1 failed.
- Raft `check.sh` files run only at `tracker.sh check` and `done` for their own raft. After R0040 merges, no check in the repo stops the next raft's client adapter from requiring into ServerScriptService. That require errors at runtime, because ServerScriptService doesn't replicate, and nothing catches it before Studio.
- The rule sits in the skill as documentation only, and the skill itself says the static checks can't tell the targets apart.
Fix:
- Add a rule to `tests/meta/architecture.spec.luau`: "src requires use only relative paths, `@self/` or `@game/ReplicatedStorage/`". Scan `graph.listLuau("src")` with `graph.stripComments` and `graph.REQUIRE_PATTERN`, and reject any `@` spec outside those two prefixes. It's about 12 lines.
- Add `tests/meta/architecture.spec.luau` to Touched modules.
- Reword the skill bullet to say `tests/meta` enforces the rule.
- Keep RC1 as the Checked proxy. It passes vacuously today, but it pins the same rule externally.

### F3 [low] place-game's "works on the Rojo-built place" passes on unmodified main
Where: `place-game.spec.luau:67-74`.
Evidence: both assertions expect nil: `Shared/Logic` is a Folder and `Server/Main` is a Script. Today's `resolveRequire` returns nil for every alias, so the case passes without the change. On main, place-game runs 4 passed and 1 failed, and this case is one of the 4. Nothing proves that `@game` walks up to a real deserialized DataModel and down through its services. `src` has no ModuleScript to aim at yet.
Fix: in that case, create a ModuleScript `Probe` with Source `"--!strict\nreturn nil"` and parent it to `ReplicatedStorage.Shared`. Assert that `place.resolveRequire(mainScript, "@game/ReplicatedStorage/Shared/Probe")` is that instance. Set `Probe.Parent = nil` in a pcall cleanup path. The place is cached per process, and the c0020 place rules require every script to start with `--!strict`.

### F4 [low] `$path` normalization is designed but not pinned
Where: Design `GameRoot.path` ("the node's normalized `$path`"); `graph-game.spec.luau:14`.
Evidence: with the mutation that stores `v["$path"]` raw, all 12 cases still pass, because every fixture and `default.project.json` path is already clean. A later `"$path": "./src/shared"` would then produce dependency keys like `./src/shared/Logic/X/init.luau`. Those match no file in `g.files`, so the meta features rule and the affected selector silently miss the edges.
Fix: write `PROJECT`'s Shared node as `["$path"] = "./tests/fixtures/graph/"`, and keep the expected `rootsMap` value `tests/fixtures/graph`.

### F5 [low] The skill's rule 5 heading will contradict the new bullet
Where: c0390 Design, "Architecture skill ... rule 5"; `.claude/skills/architecture/SKILL.md` rule 5 heading "Requires are string literals, with relative paths or `@self`."
Evidence: the Design adds a bullet allowing `@game/ReplicatedStorage/`, but it leaves the heading, which still reads as an exhaustive list. A reader who skims only the headings is told `@game` is illegal.
Fix: tell the executor to amend the heading to "Requires are string literals: relative paths, `@self`, or `@game/ReplicatedStorage/` across Rojo roots."

Notes (no finding):
- **Working tree**: `scripts/check.sh --full` and all of R0050's `check.sh` leave only gitignored files. `graph-build` removes `.cache/c0390-graph` on both paths.
- **Order**: `graph-build` stubs `graph.gameRoots` before `graph-game` in the same process, and restores it. The prototype's cache lives behind the real function, so the stub never poisons it.
- **Executability**: apart from F1 to F5, the Design, the steps and the checks are enough to deliver this without asking a question.

Verdict: changes
