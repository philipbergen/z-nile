---
name: testing
description: How pickman is tested - spec tiers and naming, the affected-test selector, gate modes, check.sh acceptance files and their sequestration. Read before writing specs, check.sh files, or running the gate.
---

# Testing

## Running tests
| command | use |
|---|---|
| `scripts/check.sh` / `--affected` | while iterating: format, lint, types for src (Roblox definitions) and tests/scripts (Lune definitions), rojo build, and **only the affected specs** |
| `scripts/check.sh --full` | every spec. Used by raft `check.sh` files and by CI |
| `lune run tests/run -- <spec files>` | specific specs |
| `lune run scripts/affected -- [--base REF] [files…]` | show which specs a change selects (`ALL` = full run) |
| `scripts/tracker.sh check <id>` | an item's acceptance checks |

## Spec layout (`*.spec.luau`)
| dir | tier | may require |
|---|---|---|
| `tests/unit/<Feature>/` | one feature's behavior | only that feature (through its `init`) plus `@tests/lib/t` |
| `tests/contract/<Consumer>__<Provider>.spec.luau` | the Provider API exactly as the Consumer relies on it | the Provider only |
| `tests/integration/` | a few headless cross-feature checks that don't step time (see Simulations) | several features |
| `tests/scenario/` | story-style simulations through `@tests/lib/sim` | Logic features, `@tests/lib/sim`, `@tests/lib/t`, `@tests/fixtures/...`. Never adapters (they use Roblox globals) |
| `tests/tooling/` | the scripts in `scripts/` | scripts |
| `tests/place/` | the Rojo-built DataModel, loaded headlessly via `@tests/lib/place` (structure, script classes, require resolution as Roblox does it). Selected for every `src/` or `default.project.json` change | `@tests/lib/place` |
| `tests/acceptance/<id>/` | acceptance specs promoted by `tracker.sh done`. Never edit these; if one is wrong, file a chore (test fixes are always chores) | anything, via aliases |
| `tests/meta/` | the structural rules from the architecture skill | the graph library |

A spec file looks like this:
```lua
--!strict
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

return t.spec("Maze.parse", function(it)
	it("rejects rows of unequal width", function()
		t.expect(function() Maze.parse({ "##", "#" }) end).toThrow("width")
	end)
end)
```
The assertions are `toBe`, `toEqual` (deep), `toBeNear`, `toBeTruthy` and `toThrow(pattern?)`.

**Good specs**:
- **Deterministic**: no wall-clock time and no unseeded randomness. Pass `dt` and a seeded RNG instead. The one timing exception is `sim.bench` budgets (see Simulations).
- **One behavior per case**, with a name that states it.
- **Assert on public API results**, never on internals.
- **Hard to fake.** An acceptance spec must fail for plausible wrong implementations: an off-by-one, a missing edge case, a hard-coded value. Include at least one case that a hard-coded or partial implementation would fail.

## Simulations (`@tests/lib/sim`)
`tests/lib/sim.luau` runs any **model** (`new(seed)`, `step(state, intents, tick)`, `observe(state)`, plus `name` and `tickRate`) for N ticks from a script of timed intents and expectations, and returns a trace. The game's Logic provides a model; `tests/fixtures/sim/walker.luau` is a small one.

**Tick semantics** (the contract every model must follow):
- Time `t` is the world after `t` steps. Time 0 is `model.new(seed)`.
- Step k moves the world from time k to time k+1.
- An intent at k is delivered in step k. Several intents at one tick arrive in script order; a step with none gets an empty list.
- Events returned by step k are visible at time k+1, so they are stamped `tick = k+1`.
- An expectation `at = t` is checked against the observation at time `t` (`at = 0` is the initial state). Per time the order is: record, check expectations, then `stopWhen`.

```lua
local sim = require("@tests/lib/sim")
local Walker = require("@tests/fixtures/sim/walker")
local trace = sim.run(Walker, {
    seed = 1,
    ticks = sim.ticks(Walker, 0.5),
    script = { sim.intent(0, "R"), sim.expect(5, { x = 10 }, "reaches the wall") },
})
t.expect(sim.firstTick(trace, "Bump")).toBe(6)
```
- A table expectation is a partial match on top-level keys only; a function expectation gets a copy of the observation and fails by raising.
- Observations and intents are **deep-copied**: the harness snapshots each observation, and each run gets fresh copies of the scripted intents.
- **JSON-safe**: intents, observations and events must be JSON-safe (no functions, sparse arrays or NaN), because failures write a replay.
- Misuse (bad `ticks`, `seed` or `at`, an intent or expectation beyond the run) fails before any step.
- `sim.assertDeterministic` runs a scenario twice and names the first diverging tick. `sim.seeds(n)` and `sim.firstTick` support measurable proxies for feel: "an idle player is caught within N-M s across 20 seeds" goes here, not in Observed.
- **Replays**: a failure writes `.cache/sim/<model>-seed<seed>-tick<t>.json` (gitignored) and names it in the message. To debug, re-run it from a scratch spec: `sim.replay(Model, ".cache/sim/…json")`. It re-runs the model, so a `print` in the model works; for a step error the failing step runs again and re-raises.
- **`sim.bench`** steps N worlds interleaved, like the server, and returns elapsed seconds. Budgets are the one **timing exception** to "no wall-clock time": keep a margin of at least 50x over the measured cost.

**Choosing a tier**: anything driven through `@tests/lib/sim`, including whole-level simulations, goes in `tests/scenario/`. `tests/integration/ is for` cross-feature checks that don't step time.

## Affected selection
`scripts/affected.luau` builds the static require graph of `src/` and `tests/`. It selects every spec whose transitive requires include a changed file.
- **Full run**: changes to `tests/lib`, `tests/run.luau`, `tests/meta`, `scripts/`, or any config file (`.luaurc`, `rokit.toml`, `default.project.json`, `selene.toml`, `stylua.toml`) force one.
- **Reliability** depends on the architecture rules: literal requires, and features used only through `init`. `tests/meta` enforces those rules.
- **Graph miss**: a spec fails under `--full` but wasn't selected for the same diff. That's a selector bug. File it as a chore, since CI and test bugs are always chores: `tracker.sh new issue c affected-graph-miss-…`.

## Acceptance checks (`check.sh`)
Every issue and raft has a `check.sh` that uses `scripts/lib/ac.sh`:
```bash
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance"
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"
check "AC1: ghosts never reverse outside mode changes" lune run tests/run -- "$A/reverse.spec.luau"
check "AC2: Logic stays engine-free" lune run tests/run -- tests/meta/architecture.spec.luau
finish
```
- **One `check` per Checked criterion.** The label starts with the AC number from the document.
- **Exit criteria**: a raft's `check.sh` runs `scripts/check.sh --full`, then every member's `check.sh`, then the raft's own RCn checks.
- **Commands**: checks may run any deterministic command, such as a spec, a `lune run` script, `rojo build`, or a `grep` that must match nothing.
- **Where acceptance specs live**: ticket-prep writes them in the issue's `acceptance/` folder (`tracker/issues/<id>/acceptance/*.spec.luau`), **not** in `tests/`.
  - They target code that doesn't exist yet, so putting them in `tests/` would turn main red.
  - They're formatted and linted, but not type-checked or run by the repo gate. Only `check.sh` runs them, by explicit path.
  - They must require only through aliases (`@logic/…`, `@tests/…`, `@scripts/…`), never relative paths, because they get moved.
  - Never write literal `require("…")` text inside strings or comments. The graph scanner would treat it as a real require. Build such text by concatenation.
  - `tracker.sh done` **moves** them to `tests/acceptance/<id>/`, where they become permanent regression specs. It then type-checks `tests/`, runs `tests/meta` and the promoted specs, and **rolls back** if any of that fails.
- **Sequestered**:
  - `check.sh` files and the acceptance specs they name are written in ticket-prep, *before* execution.
  - During execution they must not change.
  - The code reviewer diffs them against the `tracker: start` commit.
  - If one is actually wrong, the executor stops and escalates; it doesn't patch it.

## Criteria tiers (in each issue document)
- **Checked**: deterministic and in `check.sh`. Nearly everything belongs here.
- **Judged**: genuinely subjective, with a written rubric. The adversarial code reviewer gives a pass/fail ruling in `review-NNN.md`.
- **Observed**: the minimum set of Studio playtest steps for the human.

If something could be expressed as a measurable proxy, it's not Judged or Observed. For example, "ghost pursuit feels fair" can become "an idle player is caught within 6–12 s across 20 seeds".

## Hooks (Claude Code only)
- After every `.luau` edit: stylua formats the file and selene lints it.
- On stop: `scripts/check.sh --affected` runs if `src/` or `tests/` changed.
