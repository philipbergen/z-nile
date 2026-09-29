---
id: c0020
type: chore
title: Headless place tests
raft: R0010
depends_on: []
emergent: false
design: reviewed
created: 2026-09-28
---

# c0020: Headless place tests

## Problem
Lune tests prove that pure Logic works, but nothing proves that **what Rojo builds** matches our assumptions about Roblox. Examples:
- a script in the wrong service;
- a `Script` accidentally created in ReplicatedStorage;
- a string `require` that resolves on the filesystem (Lune) but not in the DataModel (Roblox), because an `init.luau` becomes a ModuleScript *parent*.

Each of these is found today only by a human in Studio. That makes Observed criteria the default, which is expensive and slow. Experiment E1 (below) showed that Lune's `@lune/roblox` can load the built `.rbxl` and inspect the instance tree, including script sources, with no Studio.

## Non-goals
- Executing game code inside a Roblox engine. That needs Open Cloud Luau Execution, which requires an API key and a published place; it's follow-up c0030.
- Physics, rendering or replication behavior.
- Testing adapters' runtime behavior. This issue covers **structure and resolution** only.

## Solution
Add a test tier, `tests/place/`, whose specs load the Rojo-built DataModel through a shared helper and assert structural rules. That includes a **Roblox-semantics require resolver** that checks every string require in every script resolves to a ModuleScript in the DataModel. `affected` learns that place specs depend on all of `src/` and on `default.project.json`, even though they don't `require` them.

## Design

**`tests/lib/place.luau`** (new; test infrastructure, so changing it forces a full run):
```lua
export type Instance = any -- @lune/roblox Instance
-- Builds default.project.json with `rojo build` into .cache/place-test.rbxl once per process,
-- deserializes it with @lune/roblox and returns the DataModel (cached for the process).
function place.load(): Instance
-- Every LuaSourceContainer under ReplicatedStorage.Shared, ServerScriptService.Server and
-- StarterPlayer.StarterPlayerScripts.Client, in GetFullName order.
function place.scripts(game: Instance): { Instance }
-- Resolve a string require the way Roblox does, from `from` (a LuaSourceContainer):
--   "@self/A/B"  -> from:FindFirstChild("A"):FindFirstChild("B")
--   "./A/B"      -> from.Parent:FindFirstChild("A")...
--   "../A"       -> from.Parent.Parent:FindFirstChild("A")   (each extra "../" goes one level up)
-- Returns the ModuleScript, or nil if any segment is missing or the target is not a ModuleScript.
-- "@lune/..." and other aliases return nil (they are not valid in src/).
function place.resolveRequire(from: Instance, spec: string): Instance?
-- String-literal require specs in a source string (same pattern as scripts/lib/graph.luau).
function place.requireSpecs(source: string): { string }
```
- **Build output**: the build writes to `.cache/place-test.rbxl`, which is gitignored. If `rojo build` fails, `place.load()` raises an error containing rojo's stderr.
- **Why a separate resolver**: `scripts/lib/graph.luau` resolves requires on the **filesystem**, which is what Lune does. `place.resolveRequire` resolves on the **instance tree**, which is what Roblox does. The place-requires spec checks that every require in `src/` succeeds under both, and that is what catches Rojo-mapping surprises.

**`scripts/lib/graph.luau`**:
- Add the constant `graph.PLACE_LIB = "tests/lib/place.luau"`.
- Extend `affectedSpecs` so that a spec whose closure contains `PLACE_LIB` counts as depending on every file under `src/` and on `default.project.json`. It's selected when any changed path starts with `src/`, or equals `default.project.json`.
- `scripts/affected.luau` then selects place specs for `src/` changes without a full run.

**`tests/place/structure.spec.luau`** (the executor's own spec) checks the project-specific layout:
- `Server.Main` is a `Script`;
- `Client.Main` is a `LocalScript`;
- `Shared.Logic` exists.

**Aliases**: `.luaurc` has the alias `@scripts` → `./scripts`, landed in prep (design-review-001 F2). Acceptance specs use `@scripts/lib/graph`. No `.luaurc` change is needed during execution.

**Selection by dependency, not directory**: `affectedSpecs` must decide from each spec's require closure, never from its path. After `done`, `tests/acceptance/c0020/*.spec.luau` also load the place library and must be selected for `src/` changes (F11). A synthetic-graph case in `affected-place.spec.luau` pins this.

**Docs**:
- Add the tier `tests/place/` to the testing skill's table.
- The architecture skill says that `tests/place` enforces "no Script or LocalScript under ReplicatedStorage".

### Scalability
- One build per test process, about 0.2 s. It stays constant no matter how many place specs there are.
- The resolver is linear in the number of scripts × requires.

### Maintainability
- Structural rules live in one tier.
- Adding a rule means adding one case. The resolver is small and has its own acceptance cases on synthetic trees.

### Usability
- Many future "Observed" criteria become Checked criteria.
- Failures name the script's full name and the require that failed.

### Touched modules
- `tests/lib/place.luau`
- `tests/place`
- `scripts/lib/graph.luau`
- `scripts/affected.luau`
- `tests/tooling/affected.spec.luau`
- `.claude/skills/testing/SKILL.md`
- `.claude/skills/architecture/SKILL.md`

### Affected specs
`ALL`, because `scripts/` and `tests/lib/` change. New specs: `tests/place/structure.spec.luau`, plus the acceptance specs below.

## Unknowns & experiments
- **E1 (run in prep: PASS)**: can `@lune/roblox` `deserializePlace` read a `rojo build` output and expose `ClassName`, `Name`, `Source` and hierarchy?
  - Result on 2026-09-28: `ServerScriptService.Server` is a Folder, `Server.Main` is a Script with 123 bytes of Source, and `StarterPlayerScripts.Client.Main` is a LocalScript.
- **E2 (run in prep: PASS)**: can `roblox.Instance.new` build synthetic trees (Folder, ModuleScript, `.Parent`, `.Source`, `GetFullName`, `IsA("LuaSourceContainer")`) for resolver tests?
  - Result: yes. `Logic.Maze.Grid`, and `IsA` returns true.
- **E3 (not testable headless; accepted risk)**: does Roblox's require-by-string treat `./` from a ModuleScript as its Parent's children, and `@self` as its own children, exactly as designed above?
  - The design follows Roblox's documented require-by-string semantics.
  - OC1 confirms it in Studio once, the first time a real feature adds relative requires. Until then there are no relative requires in `src/`.
  - Fallback if Studio disagrees: change `resolveRequire` and file a defect.

## Regression guard
- **Existing specs**: `tests/tooling/affected.spec.luau` must still pass unchanged, and the executor adds a case to it for the implicit place dependency. `tests/meta/architecture.spec.luau` must stay green.
- **Selector coverage**: the acceptance spec `affected-place.spec.luau` pins `affected`'s new implicit dependency, so a future selector change can't silently drop place specs.

## Test plan
- **`acceptance/resolve-require.spec.luau`**, on synthetic trees: `@self child` → AC1; `./ sibling` → AC1; `../ uncle` → AC1; `missing segment is nil` → AC1; `non-ModuleScript target is nil` → AC1; `aliases are nil` → AC1.
- **`acceptance/place-rules.spec.luau`**, on the built place: `every src script is strict` → AC2; `no Script/LocalScript under Shared` → AC2; `every require in src resolves in the DataModel` → AC2.
- **`acceptance/affected-place.spec.luau`**: `a src change selects place specs, not unrelated unit specs` → AC3; `a default.project.json change selects place specs` → AC3; `selects by dependency on the place library, not by directory` (synthetic graph) → AC3; `an unrelated change does not select place specs` → AC3.
- **`tests/place/structure.spec.luau`** (the executor's own): Main scripts' classes, and Logic exists.

## Acceptance criteria

### Checked
- **AC1**: `place.resolveRequire` implements Roblox require-by-string semantics on instance trees.
- **AC2**: The built place satisfies the structural rules: strict scripts, no runnable scripts in Shared, and every src require resolves in the DataModel.
- **AC3**: The affected-test selector selects place specs for changes to `src/` or `default.project.json`.

### Judged
None.

### Observed
- **OC1**, only when a later raft first adds a relative require in `src/`: `rojo serve`, connect Studio, press Play. The Output window shows no require errors, and both `[pickman] … started` lines appear.
  - This is recorded here so that raft's design can pick it up. It doesn't block this raft.

## Implementation steps
1. `tests/lib/place.luau`: load, cache, scripts, requireSpecs, resolveRequire.
2. Make the AC1 acceptance spec pass. Commit.
3. `tests/place/structure.spec.luau`. Make the AC2 acceptance spec pass. Commit.
4. `graph.PLACE_LIB` and implicit dependencies in `affectedSpecs`. Add the fixture case to `tests/tooling/affected.spec.luau`. Make AC3 pass. Commit.
5. Update the skills' docs. Run `scripts/tracker.sh check c0020`.

## Verification log
