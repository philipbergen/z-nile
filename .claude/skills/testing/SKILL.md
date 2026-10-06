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
| `lune run tests/run -- --jobs N` / `PICKMAN_JOBS=N` | spec concurrency (default `min(max(cpus,2),8)`; `1` is serial, a bad value exits 2) |

## Spec layout (`*.spec.luau`)
| dir | tier | may require |
|---|---|---|
| `tests/unit/<Feature>/` | one feature's behavior | only that feature (through its `init`) plus `@tests/lib/t` |
| `tests/contract/<Consumer>__<Provider>.spec.luau` | the Provider API exactly as the Consumer relies on it | the Provider only |
| `tests/integration/` | a few headless cross-feature checks that don't step time (see Simulations) | several features |
| `tests/scenario/` | story-style simulations through `@tests/lib/sim` | Logic features, `@tests/lib/sim`, `@tests/lib/t`, `@tests/fixtures/...`. Never adapters (they use Roblox globals) |
| `tests/tooling/` | the scripts in `scripts/` | scripts |
| `tests/runtime/` | scripts that run inside a real Roblox server of the published Beta place, through Open Cloud's Luau Execution API (`lune run scripts/runtime-test -- <version>`, run by CI after a publish; skipped when no key is configured). Each returns `"PASS"`, requires nothing, and is strict Luau | nothing (Roblox globals only, via `getfenv()`) |
| `tests/place/` | the Rojo-built DataModel, loaded headlessly via `@tests/lib/place` (structure, script classes, require resolution as Roblox does it). Selected for every `src/`, `default.project.json` or `lobby.project.json` change. `place.load()` is the game place, `place.load("lobby.project.json")` the lobby; each is built once per process | `@tests/lib/place` |
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

**Running an adapter's real source**: `@tests/lib/fakeengine` loads an adapter from a built place (`luau.load` with a fake environment) and runs it against a fake engine: instances whose remotes and attributes come from that place, signals whose handlers run in coroutines, `task.*` on a fake clock, and the real Logic. It covers what the lobby adapters use (f0061's design lists the surface). A spec that needs more extends the fake, without making it accept less, or more, than it does now.

**Good specs**:
- **Deterministic**: no wall-clock time and no unseeded randomness. Pass `dt` and a seeded RNG instead. The one timing exception is `sim.bench` budgets (see Simulations).
- **One behavior per case**, with a name that states it.
- **Assert on public API results**, never on internals.
- **Survive a compaction** (`tracker.sh compact` renumbers every item): a spec that pins a real tracker item maps its id through `tests/lib/renamed.luau` (`renamed.id("R0010")`), and test data that names a `tests/acceptance/<id>` path spells it in two parts (`"tests/" .. "acceptance/"`), or the compaction rewrites it.
- **Hard to fake.** An acceptance spec must fail for plausible wrong implementations: an off-by-one, a missing edge case, a hard-coded value. Include at least one case that a hard-coded or partial implementation would fail.
- **No browsers.** `tests/run` puts recording `open` and `xdg-open` stubs first on `PATH` for the whole run (workers and nested runners included, through `PICKMAN_OPEN_GUARD`) and fails the run if any is called. Run `tracker.sh board` with `-O`; a spec that tests opening puts its own stubs first on `PATH`. A spec that sets `PATH` for a child prepends to it, never replaces it, or the guard's stubs are lost.

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

## Affected selection
`scripts/affected.luau` builds the static require graph of `src/` and `tests/`. It selects every spec whose transitive requires include a changed file.
- **Full run**: changes to `tests/lib`, `tests/run.luau`, `tests/meta`, `scripts/`, or any config file (`.luaurc`, `rokit.toml`, `default.project.json`, `selene.toml`, `stylua.toml`) force one.
- **Reliability** depends on the architecture rules: literal requires, and features used only through `init`. `tests/meta` enforces those rules.
- **Graph miss**: a spec fails under `--full` but wasn't selected for the same diff. That's a selector bug. File it as a chore, since CI and test bugs are always chores: `tracker.sh new issue c affected-graph-miss-…`.

## Acceptance checks (`check.sh`)
Every issue and raft has a `check.sh` that uses `scripts/lib/ac.sh`:
```bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
A="$HERE/acceptance" # sequestered specs: here before `tracker.sh done`, promoted after it
[[ -d $A ]] || A="$PWD/tests/acceptance/<id>"
check "AC1: ghosts never reverse outside mode changes" lune run tests/run -- "$A/reverse.spec.luau"
check "AC2: Logic stays engine-free" lune run tests/run -- tests/meta/architecture.spec.luau
finish
```
- **Must run after promotion**: a `check.sh` is re-runnable once `tracker.sh done` has moved its specs, which is what the fallback line is for. `AC_LIST=1 bash <check.sh>` lists a script's checks (`LIST  <label>`) without running them and ends with `n criteria listed (none run)`; `tests/run`, `tracker.sh check` and `tracker.sh done` refuse to run while `AC_LIST` is set.
- Work outside `check` is limited to running a spec through `tests/run` (which list mode refuses), `tracker.sh members` and other cheap reads; everything else goes inside `check`.
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
  - The code reviewer checks them with `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'`, which must list only `R100` renames (review skill, Code mode item 2).
  - If one is actually wrong, the executor stops and escalates; it doesn't patch it.

## Criteria tiers (in each issue document)
- **Checked**: deterministic and in `check.sh`. Nearly everything belongs here.
- **Judged**: genuinely subjective, with a written rubric. The adversarial code reviewer gives a pass/fail ruling in `review-NNN.md`.
- **Observed**: the minimum set of Studio playtest steps for the human.

If something could be expressed as a measurable proxy, it's not Judged or Observed. For example, "ghost pursuit feels fair" can become "an idle player is caught within 6–12 s across 20 seeds".

## Speed
A standing rule, not a one-off. Tests and checks run very often, so they must run **concurrently** and as swiftly as possible.
- **What exists**: `scripts/lib/par.sh` runs the independent static stages together (`par_start` / `par_wait`: buffered, timed, reported in start order); `tests/run` runs spec files in concurrent workers (`--jobs N`, `PICKMAN_JOBS`). `PICKMAN_JOBS=1` restores serial runs when you suspect an ordering bug.
- **Monitor continuously**: every gate run prints per-stage times, a `slowest:` line and `gate wall time:`, and whoever runs it looks at them. A stage or spec that dominates, or a time that creeps up between runs, is a gate defect: **optimise** it now if it is in your Touched modules, otherwise file a chore (`tracker.sh new issue c gate-slow-<what>`). Never add a serial dependency between stages without a reason.
- **Writing specs for speed**: no wall-clock assertions and no fixed sleeps to let something finish (a bounded poll or rendezvous with a timeout is fine). Shell-heavy fixtures own a unique `.cache/<name>` (a literal `.cache/<dir>` in two spec files under `tests/` fails the gate, a mere mention counts, and `sim` is exempt). No shared mutable state across spec files. Prefer in-process Logic specs, and split or stub a spec that takes more than about a second. Two suites in one checkout queue on the runner's lock; separate worktrees run in parallel (see "Specs never touch the real repository").

## Specs never touch the real repository
On 2026-09-30 two suites in one worktree deleted each other's fixtures. Fixture git commands then ran in the real repository, removed `origin` for every session, and committed an agent's work onto a fixture branch. While these guards were being built, a spec run against the unguarded runner did it again: it rewrote the shared identity and committed onto a branch. So the repository a check runs in is off limits to every spec, `check.sh` and script a check runs.
- **Protected**: the main checkout, every worktree of it, and the git directory they share (config, refs and branches, HEADs and indexes, the worktree registry, objects, and every file), and the person's own git configuration (`~/.gitconfig`, `~/.config/git`). **Allowed writers**: `.cache/` (fixtures and build output), the gate's `sourcemap.json`, and the transient copies that `tracker.sh promote-check` makes in `tests/acceptance/` and removes before it exits. The last two are written by `check.sh` files, never by specs.
- **Fixtures**: anything a spec changes lives under `.cache/<name>`, unique to the spec file, in a repository of its own (`git init`, or a `--no-hardlinks` clone through `@tests/lib/clone`). Fixtures commit as `<name>@example.invalid` (`-c user.name=… -c user.email=…`, or local config in the fixture), and never write an identity anywhere else. Run git and `tracker.sh` in a fixture only through `@tests/lib/fixture` (`fixture.git`, `fixture.exec`): it refuses, before anything runs, a directory that isn't a fixture repository under this run's `.cache` (if the fixture's repository were missing, git would find the real one) and anything that points git elsewhere (`-C`, `--git-dir`, `--work-tree`, or a git-directory variable in `env`). Raw git only for `rev-parse`, `ls-files`, and `init` or `clone` to a named path; no shell strings (`sh -c`), no `process.create`. `retrofit.spec` keeps the twelve older fixture specs on the helper. Written before it and not converted yet: c0510's specs (R0200), and c0640's and c0650's, which check each fixture themselves; convert them when they are next edited. Against the real repository, only read: `rev-parse`, `ls-files`, `ls-tree`, `show`, `log`, `diff`, `cat-file`, `for-each-ref`, and cloning *from* it.
- **Enforced at run time** for every spec, by `tests/run` (`tests/lib/fence.luau`, `scripts/lib/fence.sh`):
  - **Jail (macOS)**: specs run under `sandbox-exec`. The kernel denies every write to the checkout, the main checkout, their shared git directory, every repository an outer guard protects (a copy of the tree under `.cache` runs its own gate), and the person's git configuration, except this checkout's `.cache`. In fact it denies every write outside this checkout's `.cache` (but not the `.cache` entry itself, which must stay a plain folder: the runner and `fence.sh` refuse a symlinked one), the run's own temp folder (a fresh `pickman-run.*` under the shell's temp folder, given to specs as `TMPDIR`, with a `mktemp` that uses it, and removed after the run) and `/dev`. Every other temp folder (`/tmp`, the user temp folder) is closed, because programs outside the jail run and copy files from them. `fence.sh` never deletes recursively. Also closed: the folders above the repository (none can be renamed away, written and renamed back), and the person's home (tools such as the runner itself, shell start-up files, settings, launch agents, which all run later without the jail). It also denies IP networking except loopback, so a spec's `-c protocol.allow=always` reaches nothing while local test servers work; specs also run with no proxy and with `GIT_ALLOW_PROTOCOL=file`. An outer sandbox is accepted only if probes show it closes all of that too. Nothing a spec does can change the repository: git in any form, a plain file write, a missing fixture. A run that can't be jailed refuses to start, before any spec runs, unless it proves by probes that it can't write the repository (an outer sandbox denies it), or that it is a fixture of a jailed outer run (an outer guard's repositories are unwritable from it, and it lies under that checkout's `.cache`; an ancestor in `GIT_CEILING_DIRECTORIES` proves nothing). Runs can't be jailed inside another sandbox, which macOS can't nest, or without `sandbox-exec`. So in a sandboxed agent shell, run specs with that sandbox off. `PICKMAN_TEST_JAIL` says which applies, and the gate's jail case probes the same writes.
  - **Fence**: git never looks above `<checkout>/.cache` for a repository, and a sentinel `.cache/.git` makes git fail in `.cache` itself. A fixture whose repository is missing is an error, never the checkout.
  - **Overrides stripped**: an inherited `GIT_DIR`, `GIT_INDEX_FILE` or the like (git hooks run with them set) is unset before any spec runs.
  - **Ref guard**: every git a check runs has a `reference-transaction` hook (`scripts/lib/git-hooks/`) that refuses any ref update in the real repository. Only a `check.sh` flow started outside any spec run may fetch (create or move refs under `refs/remotes/`), as `scripts/ci-verify.sh` does. On Linux this is what stops a commit, branch, switch or reset there. It refuses the ref change, but those commands may already have rewritten the index or the working files. The hooks are set only where there is no jail (Linux, `check.sh` files, runs nested inside a jail): under the jail the kernel covers it, and a hook in every fixture commit would cost a slow process start. Where they are set, they then run the repository's own hook of the same name, so a fixture's hooks behave as without the guards.
  - **No network for specs**: a `pre-push` hook refuses pushes into the real repository by any local URL. During spec runs it allows a push only into an existing local repository that isn't protected, so https, ssh, `host:path` and ssh aliases are all refused. With or without hooks, spec runs also allow git no network transport at all (`protocol.allow=never`, local paths and `file://` only), however a URL is spelled or aliased. Specs also get no credentials: `GH_TOKEN` and the like are unset, `GH_CONFIG_DIR` is empty, the git credential helper list is reset (no keychain), and there is no ssh agent and no ssh. A `check.sh` started from inside a spec run keeps these limits.
  - **No publishing from checks**: a tracker command run by a check never publishes tracker state: the publisher asks `pickman_guarded` (`scripts/lib/fence.sh`), says `not publishing`, and goes on as with `PICKMAN_PUBLISH=0`.
  - **Lock**: one run at a time per checkout (`.cache/tests-run.lock`), because runs share the `.cache` fixtures. Separate worktrees still run in parallel. A second run prints `waiting for another test run (pid N)` and waits up to `PICKMAN_TEST_LOCK_WAIT` seconds (default 240). A lock whose every process is gone is taken over.
  - **Tripwire**: a run refuses to start while the repository's identity is a fixture's. It fails with `REPOSITORY CHANGED`, even when every case passed, if any of these happened during it:
    - remote, core or user config changed (gh's `gh-resolved` aside);
    - this checkout switched branch;
    - its HEAD lost history or gained commits a fixture wrote;
    - a worktree appeared under `.cache`;
    - a ref whose tip a fixture identity wrote appeared.
  - **Gate spec**: `tests/tooling/repo-fence.spec.luau` proves in every gate that the guards are on, the jail included (harmless probe writes outside `.cache` must fail). It scans what runs as a check (`tests/`, `scripts/` and every `check.sh`; a prepared acceptance spec once it is promoted into `tests/`), case-insensitively. It fails if any of them names a way to switch the guards off (`GIT_CEILING_DIRECTORIES`, `GIT_DIR`, `GIT_CONFIG_*`, `core.hooksPath`, `--no-verify`, `sandbox-exec`, `env -i`, `osascript`, `launchctl`, and the network and credential settings `protocol.*allow`, `credential.*`, `extraheader`, `GIT_SSH_COMMAND`, …), or commits as anything but `@example.invalid` (in `user.email` or an `*_EMAIL` variable). Extensionless files (hooks, tools) are read too; the guards themselves (`scripts/lib/git-hooks/`, `fence.sh`, `fence.luau`) are exempt. A file with a real need to name one (a fixture hook that unsets what git exports to it, the fixture helper that refuses them) gets an entry in the spec's `ALLOWED` table: that file, those names only, and the reason. The review checks every entry.
- **`check.sh` files** get the fence, the override stripping and the ref and push guards through `ac.sh`, but no jail: they legitimately write the checkout (`sourcemap.json`, `promote-check`) and talk to GitHub (`scripts/ci-verify.sh`). The specs they start are jailed.
- **Caught only by review** (the review skill's Repository safety item; each is **high**):
  - **Linux (CI)**: specs there are unjailed, so a write to the real checkout's index or files (`git add`, `checkout`, `reset --hard`, `worktree remove`, `remote set-url`, a plain file write) is stopped by nothing; CI's checkout is disposable, but the same spec runs on developers' Macs, where the jail stops it.
  - **`check.sh` files' own commands**: anything they run outside `tests/run`, including config writes and network actions.
  - **Handing work to a process outside the jail**: `open`, `osascript`, `launchctl`, or a daemon. The gate scan flags `osascript` and `launchctl`.
  - **A process that leaves the run's process group** (`setsid`, a double fork into a new session): the runner stops what is left in the specs' group when they end, but not this. It stays jailed, yet it outlives the run and could change files in `.cache` that an unjailed `check.sh` later copies and runs (a copy of the tree under `.cache`).
- **Running specs against unguarded code**: only in a clone under `$TMPDIR`, outside every repository (`git clone --no-hardlinks . "$(mktemp -d)/repo"`). That applies when prototyping the guards themselves, or on a branch from before them. A broken fixture there can only reach the clone.
- **If the tripwire fires**, or the shared remotes, branches, worktrees or identity look wrong: stop, post `BLOCKED:` with the output, and never repair the shared repository yourself. Every worktree and session shares it.

## Hooks (Claude Code only)
- After every `.luau` edit: stylua formats the file and selene lints it.
- On stop: `scripts/check.sh --affected` runs if `src/` or `tests/` changed.
