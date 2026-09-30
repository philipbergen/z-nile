# Review 003: R0050 (design mode)
Inputs: working tree on main @ 360511a (uncommitted): `tracker/rafts/R0050/{R0050-game-alias-requires.md,check.sh,design-review-00{1,2}.md,design-refute-00{1,2}.md}`, `tracker/issues/c0390/{c0390-game-alias-requires.md,check.sh,acceptance/*.spec.luau}`, `scripts/lib/graph.luau`, `scripts/affected.luau`, `tests/lib/place.luau`, `tests/meta/architecture.spec.luau`, `.luaurc`, `default.project.json`, the architecture/testing/tracker/review skills, `tracker/architecture.md`, R0040 raft and f0120/f0130 (context).
Dropped from review-002: F1, F2, F3, F4, F5
Method: I built a fresh prototype of the c0390 Design in a scratch worktree (`/tmp/r0050-review3`, since removed). It had graph (about 70 lines), place (6 lines), the `tests/meta` case (11 lines) and a skill edit. Results:
- c0390 `check.sh` passes 5/5.
- R0050 `check.sh` passes 4/4: the full gate, c0390, promote-check and RC1.
- After the runs, `git status` showed only the intended edits.

Round-2 answers verified against the files:
- F1: `graph-game.spec.luau:46-53` asserts the instance-length order. The fixture has the `StarterPlayer/.../Client` root, and lines 95-97 assert both `Client/Main` and `Client/Main.client` → nil.
- F2: the `tests/meta` case, `graph.srcAliasAllowed` and AC5 are in the Design. The new F1 below is about how weakly AC5 checks that case, not about whether it exists.
- F3: `place-game.spec.luau:74-85` adds and removes a `C0390Probe` ModuleScript on the built place. That case fails on main.
- F4: the fixture's `./tests/fixtures/graph/` depends on normalization.
- F5: the heading amendment is in the Design's "Architecture skill" section.

### F1 [high] AC5's "tests/meta applies it to every require in src" passes with a dead meta rule, so the permanent guard can ship broken
Where: `tracker/issues/c0390/acceptance/src-aliases.spec.luau:46-49`; c0390 `check.sh` AC5; c0390 AC5 ("and `tests/meta` applies it to every require in `src`").
Evidence: the only check on the `tests/meta` side is a substring test: `string.find(meta, "graph.srcAliasAllowed")`. AC5 also runs `tests/meta/architecture.spec.luau`, but `src` has no requires today, so any version of the new case passes vacuously. In the prototype I made the rule dead by changing its condition to `if graph.srcAliasAllowed(spec) and false then`. I also added a module `src/server/Secret.luau` and a client module `src/client/Bad.luau` that does `require("@game/ServerScriptService/Server/Secret")`, a violation that resolves both on disk and in the place. The results:
- c0390 `check.sh`: 5/5 PASS.
- R0050 RC0 (`scripts/check.sh --full`, c0390, promote-check): PASS.
- Only R0050 RC1, the one-shot raft grep, failed.

After merge, RC1 never runs again. So a scan bug in the meta case would leave the rule review-002 F2 asked to make permanent silently inert. Examples of such bugs: a double-quote-only pattern that misses `require('@game/ServerScriptService/…')`, a missing `table.insert`, or scanning `g.deps` or unstripped source. R0040's RC3 is also one-shot. The criterion can be passed by a wrong implementation.
Fix: move the scan into graph, so that the acceptance spec pins it and `tests/meta` only wires it.
- Add `graph.srcAliasViolations(dir: string): { string }` to the Design. It returns `"<file>: <spec>"` for every `REQUIRE_PATTERN` spec in `stripComments` of each `listLuau(dir)` file where `srcAliasAllowed` is false.
- In `src-aliases.spec.luau`, write a temp dir `.cache/c0390-src` with:
  - one file of allowed requires;
  - one with `require('@game/ServerScriptService/X')`, `require( "@logic/Maze")` and a commented-out `-- require("@tests/lib/t")`.
- Assert the exact two violations, and `{}` for `"src"`. Remove the dir in a pcall cleanup, as `graph-build` does.
- Change line 48 to look for `graph.srcAliasViolations("src")`. Have the meta case be `t.expect(table.concat(graph.srcAliasViolations("src"), "\n")).toBe("")`.

### F2 [low] E3 in c0390 is stale: it says "all three acceptance specs"
Where: c0390 "Unknowns & experiments", E3 ("passes all three acceptance specs"; "graph: about 50 lines").
Evidence: there are now four acceptance specs, `src-aliases.spec.luau` included, and the raft doc's Experiments section says "all four". The prototype graph work also grew with `srcAliasAllowed` and, if F1 is taken, `srcAliasViolations`. An executor reading the issue alone gets a wrong spec count.
Fix: say "all four acceptance specs" and drop or refresh the line count.

Notes (no finding):
- **Regressions**: with the prototype, the full gate ran green (tooling, place, c0020 incl. `resolve-require` pinning `@logic`/`@lune` → nil, meta). `graph.resolve` takes the `@game/` branch before the `.luaurc` alias branch. `@Game/…` still falls to the lower-cased alias lookup, where `.luaurc` has no `game` key, so it returns nil.
- **Useful side effect**: an adapter requiring `@game/ReplicatedStorage/Shared/Logic/Maze/Grid` now resolves to a non-init file. So the existing "features are only used through their init.luau" meta rule catches it.
- **Scope**: `graph.resolve` also accepts `@game` from `tests/` and `scripts/`, where Lune can't load it. The failure is loud (a load error when the spec runs), and no R0040 spec requires an adapter, so I'm not raising it.
- **Executability**: apart from F1, the Design, the steps and the checks are enough to deliver without asking a question.

Verdict: changes
