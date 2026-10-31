---
name: pickman-test
description: How pickman's game is tested - its spec tiers (unit, contract, integration, scenario, place, runtime), the sim harness, the fake engine and the Roblox runtime tests, all from pickman's home. Read with zz-test (the gate, check.sh, the guards) before writing a game spec.
---

# Testing the game (pickman)

This is pickman's half of testing. The gate, the runner, `check.sh` files, sequestration, the affected-spec selector and the repository guards are z-nile's, in the zz-test skill, and bind here too.

## Running pickman's specs
Pickman's specs run from its home, `pickman/`: `cd pickman && lune run tests/run -- tests/unit/Maze`, or `pickman/check.sh` for pickman's whole gate (zz-test skill, Running tests). Every path below is relative to `pickman/`, where `pickman/.luaurc` points `@tests`, `@logic`, `@shared` and `@scripts` at pickman's own folders. `sim`, `place` and `fakeengine` are pickman's helpers; the assertions (`@tests/lib/t`) and `renamed` are shared, re-exported from `pickman/tests/lib/`.

## Spec tiers
| dir | tier | may require |
|---|---|---|
| `tests/unit/<Feature>/` | one feature's behavior | only that feature (through its `init`) plus `@tests/lib/t` |
| `tests/contract/<Consumer>__<Provider>.spec.luau` | the Provider API exactly as the Consumer relies on it | the Provider only |
| `tests/integration/` | a few headless cross-feature checks that don't step time (see Simulations) | several features |
| `tests/scenario/` | story-style simulations through `@tests/lib/sim` | Logic features, `@tests/lib/sim`, `@tests/lib/t`, `@tests/fixtures/...`. Never adapters (they use Roblox globals) |
| `tests/runtime/` | scripts that run inside a real Roblox server of a published place, through Open Cloud's Luau Execution API (`lune run scripts/runtime-test -- <version>`; `tests/runtime/lobby/` holds the lobby's, run with `--lobby <version>` once both places are published (c0064)). A merge runs `lune run scripts/cicd` from `pickman/`, which publishes the CICD places and runs both suites. Each returns `"PASS"`, requires nothing, and is strict Luau | nothing (Roblox globals only, via `getfenv()`) |
| `tests/place/` | the Rojo-built DataModel, loaded headlessly via `@tests/lib/place` (structure, script classes, require resolution as Roblox does it). Selected for every `src/`, `default.project.json` or `lobby.project.json` change. `place.load()` is the game place, `place.load("lobby.project.json")` the lobby; each is built once per process | `@tests/lib/place` |

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

**Running an adapter's real source**: `@tests/lib/fakeengine` loads an adapter from a built place (`luau.load` with a fake environment) and runs it against a fake engine: instances whose remotes and attributes come from that place, signals whose handlers run in coroutines, `task.*` on a fake clock, and the real Logic. It covers what the lobby adapters use (f0061's design lists the surface). A spec that needs more extends the fake, without making it accept less, or more, than it does now.

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
local t = require("@tests/lib/t")
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

## Lessons
Before you start, read this skill's lessons: `./zn lessons --skill pickman-test --full`. Each is a mistake made before, with the question that catches it.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
