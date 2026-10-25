# Review 001: R0017 (code mode)
Inputs: HEAD 23f858a (`git diff origin/main...HEAD`, origin/main 078823d), R0017.md, f0054.md, f0054/check.sh and acceptance specs (speed, adapters, docs), R0017/check.sh. Ran: `scripts/check.sh --full` (GATE PASSED, 560 passed, 91 spec files), `scripts/tracker.sh check f0054` (3/3), `bash tracker/rafts/active/R0017/check.sh` (4/4).

Sequestration: `git diff ea7e5b9 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` shows two hunks. (1) `tracker/rafts/active/R0017/check.sh`: the `spec()` fallback path changed from `tracker/issues/f0054/acceptance/$1` to `$(scripts/tracker.sh find f0054)/acceptance/$1`. That is the user-approved path-only fix. The `tests/acceptance/f0054` branch, the spec names and every `check` line are unchanged, so no check is weaker. (2) `tracker/rafts/R0009/check.sh`: the same kind of fix, but it came in with the merge of origin/main (#31, 078823d). `git diff origin/main HEAD -- tracker/rafts/R0009/check.sh` is empty, so it is not this raft's change. No other check.sh or acceptance file changed.

Design adherence: the change matches the Design exactly. `Session.GAME_SPEED = 0.5` and `STEP_RATE = TICK_RATE * GAME_SPEED` (15). `TICK_RATE` stays 30, and `newClock()` still defaults to `TICK_RATE`. `View.alpha(elapsed) = elapsed * Session.STEP_RATE` reuses View's existing Session dependency, so no new edge is added. `Sessions.luau` creates its only clock with `Session.newClock(Session.STEP_RATE)`. `Camera.luau` blends with `View.alpha(os.clock() - arrived)`. The game-design.md edits add the convention line and the Game speed bullet, and mark 7.5 tiles/s, 0.8 s, the tick rate and the run pauses as game time. Logic comments avoid the lowercase word `game` (the architecture meta rule passes). No adapter references `TICK_RATE`. The promoted tick-pinned specs (f0012/f0013/f0014, R0009) pass unchanged in the full gate, because only the clock rate the adapter asks for has changed.

Real-time audit: Movement and Session count only ticks. The only seconds-based values are `View.TURN_SECONDS` and mouse look, which stay in real time as recorded for the user to veto. `Camera.push` sets `arrived` only when the tick advances, and the server fires one snapshot per step, so a blend over 1/15 s matches the snapshot interval.

### F1 [low] Two per-step limits now mean different real-time numbers, and the docs don't mention it
Where: src/shared/Logic/Session/init.luau:41 (`MAX_STEPS_PER_ADVANCE = 5`) and :45 (`maxIntentsPerTick = 4`); tracker/game-design.md *Game speed* bullet
Evidence: Both limits count steps, so at 15 steps per real second their real-time meaning has doubled. The intent rate limit falls from 120 to 60 intents per real second per player. A frame now drops its backlog only when it is longer than 1/3 s, where before the threshold was 1/6 s. As a result, after a hitch the server catches up through up to 5 steps (1/3 s of real time) in one Heartbeat, and the client sees a bigger jump. Neither shift is wrong. No human sends 60 turns a second, and 5 catch-up steps is still bounded. But the Game speed bullet says "everything in game time takes twice as long" and doesn't mention these two non-rule limits.
Critique: An author might "fix" this by scaling the limits with `GAME_SPEED`. That would change `MAX_STEPS_PER_ADVANCE` and its promoted f0013 clock specs, which this raft deliberately leaves alone.
Consequences: Scaling would reopen f0013's tick-pinned clock specs and make `newClock()`'s defaults depend on the speed, which is exactly the coupling the Design avoids.
Recommendation: Leave the code as it is. Optionally, a later chore can add a sentence to the Game speed bullet saying that the intent rate limit and the catch-up cap are per step, so in real time they are 60 intents/s and 1/3 s. No spec is needed.

## Judged criteria (code mode only)
None in this raft.

Verdict: approve
