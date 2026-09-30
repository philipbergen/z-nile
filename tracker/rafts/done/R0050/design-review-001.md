# Review 001: R0050 (design mode)
Inputs: working tree on main @ 360511a (uncommitted): `tracker/rafts/R0050/{R0050-game-alias-requires.md,check.sh}`, `tracker/issues/c0390/{c0390-game-alias-requires.md,check.sh,acceptance/*.spec.luau}`, `scripts/lib/graph.luau`, `tests/lib/place.luau`, `tests/meta/architecture.spec.luau`, `scripts/affected.luau`, `tests/run.luau`, `scripts/tracker/main.luau` (promote-check), c0020 promoted specs, architecture/testing/tracker/review skills, `tracker/architecture.md`.
Method: I built a throwaway prototype of the c0390 design in a scratch worktree (graph about 60 lines, place 6 lines). It passes the three acceptance specs (16/16) and the full suite (`lune run tests/run`: 113 passed, 18 files). The tree stays clean apart from the gitignored `.cache/`. The acceptance specs pass selene, stylua and `luau-lsp analyze --platform=standard` with 0 errors. I then ran mutations against the acceptance specs, and the findings below cite them. I removed the worktree afterwards.

### F1 [high] AC2's "build without roots uses default.project.json" case passes on unmodified main and on an implementation that never uses the real project
Where: `tracker/issues/c0390/acceptance/graph-build.spec.luau:54-66`; c0390 AC2 ("using injected roots **or default.project.json**"); Test plan bullet "build without roots uses the real project".
Evidence:
- The case asserts `deps == {}` and `#unresolved == 2`. Today's `graph.resolve` sends `@game/...` to the generic alias branch, which finds no `game` key in `.luaurc` and returns nil. That gives exactly `{}` and 2, so the case holds with no change at all.
- Mutation M1 adds `if game == nil then return nil end` to the `@game` branch of `resolve`, so the no-roots path never consults `default.project.json`. All 16 acceptance cases still pass.
- `graph-game`'s "reads default.project.json when no project is given" pins only `gameRoots()`. Nothing pins that `resolve` and `build` default to it.
- The default path is exactly what `tests/meta` and `scripts/affected` use. With this bug, R0050 ships green and the break shows up only when R0040's first adapter requires `@game` ("every require resolves" fails). The affected selector would also silently lack the adapter-to-Logic edges.
Fix: make the default observable without writing into `src/`.
- In the design, say that `resolveGame` gets its default by calling `graph.gameRoots()` through the module table at call time.
- In graph-build case 4, temporarily replace the function: `local orig = graph.gameRoots; graph.gameRoots = function() return ROOTS end`. Then assert that `graph.build({ DIR })` records `{ "tests/fixtures/graph/A/init.luau" }` with exactly 1 unresolved (`Nope`), and restore `orig` in the cleanup path.
- Keep one assertion against the real project, for example that `graph.gameRoots()`'s `ReplicatedStorage/Shared` root is `src/shared`, which already exists in graph-game.

### F2 [medium] The cross-root rule lets both static checks accept `@game` requires that fail or misbehave at runtime
Where: c0390 Design, "Architecture skill ... rule 5" ("`src` reaches another Rojo root only through Roblox's built-in alias"); R0050 RC1 (`require("@(self|game)/`); `place-game.spec.luau:33` (a require into `@game/StarterPlayer/StarterPlayerScripts/Client/Camera`).
Evidence:
- `place.resolveRequire` walks the full, unreplicated DataModel built by Rojo, and `graph.resolveGame` maps every `$path` root. So any of these pass `tests/meta`, the c0020 place rules and RC1:
  - `src/client` code requiring `@game/ServerScriptService/Server/X`, although ServerScriptService never replicates to clients, so this errors at runtime on the client;
  - any code requiring `@game/StarterPlayer/StarterPlayerScripts/Client/X`. At runtime the running client scripts are clones under `Players.<p>.PlayerScripts`, so this loads a second, separate module instance with its own state.
- The design says a wrong path "fails in three places before Studio does". That holds for typos, but not for these, and they are the likely mistakes once `@game` is the documented way to cross roots.
Fix:
- Narrow the rule to what R0040 needs: `@game/ReplicatedStorage/` is the only allowed `@game` target in `src`.
- Write that into the skill bullet, so AC4 greps it.
- Tighten RC1's pattern to `require\("@(self/|game/ReplicatedStorage/)`, so it rejects any other `@game` target.
- Optionally, drop the StarterPlayerScripts target from `place-game.spec.luau:33`, or keep it with a comment that it is resolver coverage, not a recommended pattern.

### F3 [medium] Several of the design's stated resolution rules can be broken without failing any acceptance spec
Where: c0390 Design, `resolveGame` steps 1, 3 and 4 ("no fallback to a shorter root", "equals the rest or is a `/`-prefix of it", "exact prefix `@game/`"); `graph-game.spec.luau`.
Evidence: each of these mutations of a correct prototype still passes 16/16:
- **M3**: fall back to the next, shorter root when the longest root's file is missing. The only longest-root case, `Other/Impl`, has no file under the shorter mapping, so it can't tell the difference.
- **M6**: support no exact-root match, so `@game/<mapped instance>` is never resolved. No case requires a mapped node itself, and a `$path` directory with `init.luau` is a ModuleScript in Rojo.
- **M9**: accept `@Game/` case-insensitively. The non-goal says exact prefix only, but only `@gamer/` is tested.
- **M2**: match with a plain string prefix instead of a segment boundary. With the current fixtures it happens to return nil, but no case pins the boundary.
Fix: change the fixture so the nested node shadows a real directory, and add the cases.
- Rename `Other` to `A` and map it to `tests/fixtures/graph/B`, i.e. `Shared = { $path = "tests/fixtures/graph", A = { $path = "tests/fixtures/graph/B" } }`. Then:
  - `@game/ReplicatedStorage/Shared/A` → `tests/fixtures/graph/B/init.luau`. This covers exact-root matching and longest-wins, and fails M6, first-match and fallback.
  - `@game/ReplicatedStorage/Shared/A/Impl` → nil, because `B/Impl.luau` doesn't exist. A fallback would wrongly return `A/Impl.luau`, so this fails M3.
- Add `@game/ReplicatedStorage/SharedX/a_check` → nil for the segment boundary.
- Add `@Game/ReplicatedStorage/Shared/a_check` → nil, in both `graph-game` and `place-game`.

### F4 [low] The key Roblox claim (E2) is true but uncited, and its runtime retirement doesn't block any merge
Where: c0390 "Unknowns & experiments" E2; R0050 "Risks & rollback".
Evidence:
- E2 says "Roblox's require-by-string announcement thread on the DevForum and luau-lsp's changelog both document" `@game`, but gives no URL or quote. I verified it: https://devforum.roblox.com/t/introducing-require-by-string/3405078 carries a January 8, 2026 update: "We now support the `@game` alias, which allows require-by-string to point to the root of the DataModel", with the example `require("@game/ReplicatedStorage/MyModule")`. So the claim holds.
- The only runtime proof is R0040's f0120 OC1, an Observed criterion. Per the tracker skill, Observed criteria don't block the merge.
- The fallback is to map `src/shared` a second time into each script root. That duplicates every Logic ModuleScript, giving separate instances and state on server vs. ReplicatedStorage, and it isn't costed.
Fix:
- Put the URL and the quote into E2, so the next reader doesn't have to re-research it.
- Either get a one-minute Studio smoke test of a single `require("@game/ReplicatedStorage/...")` done before R0040 starts, or state explicitly that R0040 may merge before OC1 runs, and that the rollback then is reverting R0040.
- Note the duplicate-instance cost of the fallback.

### F5 [low] graph resolves a Script by its disk name, which diverges from the place
Where: c0390 Design, `resolveGame` step 4 ("A `Main.server.luau` script is never found, because the lookup is `Main.luau`").
Evidence: in the prototype, `graph.resolveGame("@game/ServerScriptService/Server/Main.server")` returns `src/server/Main.server.luau`. The instance is named `Main`, so `place.resolveRequire` returns nil. As a result, `tests/meta` accepts, and records an edge to, a Script. Only the c0020 place rule catches it. The existing relative-path behaviour has the same gap, but the new resolver's comment claims scripts are never found.
Fix: return nil in `resolveGame` when the resolved file ends in `.server.luau` or `.client.luau`. Add that spec to the "scripts → nil" case in `graph-game.spec.luau`.

### F6 [low] RC1's grep misses single-quoted and spaced requires
Where: `tracker/rafts/R0050/check.sh` RC1.
Evidence: the pattern `require\("@...` does not match `require('@logic/Maze')` or `require( "@logic/Maze")`. `graph.REQUIRE_PATTERN` accepts both, and so does Roblox.
Fix: use `grep -rnoE "require\(\s*[\"'][@][^\"']*" src`, and filter the allowed prefixes on the captured spec. Combine this with the F2 narrowing.

Notes (no finding):
- **Working tree:** it stays clean. `graph-build` removes `.cache/c0390-graph` on both paths, `.cache/` is gitignored, and `tests/meta` and `scripts/affected` scan only `src` and `tests`.
- **Existing specs:** `tests/tooling`, `tests/place`, `tests/acceptance/c0020` and `tests/meta` stay green with the prototype.
- **Affected selection:** it is unchanged, because the graph and place changes force `ALL`, and `default.project.json` is already a full-run trigger.
- **Cache poisoning:** the ordering of the full run (graph-build before graph-game in one process) catches a warm-cache-ignores-argument bug. AC1 run alone doesn't catch it.

Verdict: changes
