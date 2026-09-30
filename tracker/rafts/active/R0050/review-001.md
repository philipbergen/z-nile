# Review 001: R0050 (code mode)
Inputs: `git diff main...HEAD` at 4148442 (tracker start 5cd1035); R0050 raft doc and check.sh; c0390 doc, check.sh and acceptance/; architecture, testing and tracker skills. Ran `scripts/check.sh --full` (GATE PASSED, 116 passed, 19 spec files), `scripts/tracker.sh check c0390` (5/5) and `tracker/rafts/active/R0050/check.sh` (4/4). Sequestration: `git diff 5cd1035 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty.

### F1 [low] `resolveGame` accepts an explicit `init` segment that Roblox cannot resolve
Where: scripts/lib/graph.luau `graph.resolveGame` (segment loop and `.luau` lookup)
Evidence: with roots `{ { instance = "ReplicatedStorage/Shared", path = "tests/fixtures/graph" } }`, `graph.resolveGame("@game/ReplicatedStorage/Shared/B/init", roots)` returns `tests/fixtures/graph/B/init.luau`. In the place, `B` is the ModuleScript itself and has no child named `init`, so `place.resolveRequire` (and Roblox) return nil. `tests/meta` "every require resolves" would therefore pass a require that fails at runtime. The c0020 place rules in the full gate still catch it, so this is a gap in one layer, not an escape. The existing relative-path resolver behaves the same way, so the new branch copies an old gap rather than adding a new one.
Fix: in `resolveGame`, return nil when any segment after the root match is `init` (or when the last one is), matching Rojo's naming. Optionally add one negative case to `tests/tooling/game-roots.spec.luau`.

### F2 [low] `gameRoots()` returns the cached table itself, so a caller can change it for everyone
Where: scripts/lib/graph.luau `graph.gameRoots` (`return gameRootsCache`)
Evidence: `table.insert(graph.gameRoots(), { instance = "X", path = "y" })` followed by `#graph.gameRoots()` gives 4 instead of 3 for the rest of the process. No current caller mutates it, but `graph.aliases()` has the same shape and the design says the cache exists only as an optimisation.
Fix: `table.freeze` the cached list (and its entries) before storing it, or document that the result is read-only.

### F3 [low] The tooling spec's ordering case doesn't pin the tie-break
Where: tests/tooling/game-roots.spec.luau "sorts by instance path length..."
Evidence: only `roots[1]` is asserted. `A` and `C` have equal length, and the comparator's `a.instance < b.instance` tie-break is untested, so a comparator without it still passes. `table.sort` isn't stable, so without the tie-break, root order among equal lengths would be nondeterministic. That doesn't matter for correctness today (equal-length matching roots can't both be prefixes of one spec), but the tie-break is the only reason the output is deterministic.
Fix: also assert `roots[2].instance == "A"` and `roots[3].instance == "C"`.

## Judged criteria (code mode only)
None: c0390 and R0050 declare no Judged criteria.

Notes (no finding): the code matches the Design (resolve branch after `@lune/`, whole-segment longest match with no fallback, `.server`/`.client` rejection, place `@game` from the tree root with `..` rejected, `srcAliasAllowed` prefix length 24 correct after d82611b). Existing `resolve`/`build` callers are unchanged. There are no per-frame or `src` changes. The skill text carries all three AC4 phrases and the required qualifications.

Verdict: approve
