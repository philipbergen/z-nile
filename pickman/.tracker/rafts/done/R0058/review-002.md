# Review 002: R0058 (code mode)
Inputs: 8041c959 (R0058-console-gamepad, PR #152), `git diff origin/main...HEAD` (origin/main 8a58bb11), the fix delta `git diff d4abe482..HEAD` (d4abe482 added review-001), review-001.md, refute-001.md, harvest.md, the new lesson `pickman/skills/pickman-arch/lessons/folds-reset-when-their-source-changes.md`, f0146.md and its check.sh and acceptance specs, R0058's check.sh.
Dropped from review-001: none withdrawn; F1, F2, F4 and F5 are verified fixed (mutants below), F3 is fixed for its two cases and its remaining gap is F1 here.
Runs (rokit's lune 0.10.5, `export PATH="$HOME/.rokit/bin:$PATH"`, `lune --version` → `lune 0.10.5`):
- `z-nile/check.sh --full` in the worktree: lint 0 errors, 0 warnings, 0 parse errors; pickman `1433 passed, 0 failed, 213 spec files`; z-nile `1231 passed, 1 failed, 179 spec files`, the failure `tests/acceptance/c0077/replace-file.spec.luau :: content comes from stdin, …` on `Broken pipe (os error 32)`, while the machine ran about 300 lune processes (z-nile's slowest spec 1192.7 s). The branch changes nothing outside `pickman/` (`git diff --name-only origin/main...HEAD | grep -v '^pickman/'` prints nothing), and the spec alone passed three runs out of three (`14 passed, 0 failed, 1 spec files` each), so it is load, not this PR. The executor's Phase 5 gate must still be green on a quiet machine.
- `./zn check f0146`: AC1 to AC6 PASS (`6/6 criteria passed`).
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` prints nothing.
- Affected selection: `lune run z-nile/affected -- <file>` for each of `pickman/src/client/Camera.luau`, `Pads.luau`, `Sticks.luau`, `pickman/src/lobby/client/LobbyPad.luau`, `pickman/src/shared/Logic/Pad/init.luau` and `Logic/View/init.luau` selects `tests/place/camera-pad.spec.luau`, `lobby-pad.spec.luau` and `sticks-pads.spec.luau` (every `src/` change selects `tests/place`).

Mutants: in a `--no-hardlinks` clone of 8041c959 in the reviewer's scratch folder, one substitution at a time, against the three new specs, `tests/place/touch-adapters.spec.luau`, `tests/unit/Pad/pad.spec.luau` and f0146's four acceptance specs (baseline `46 passed, 0 failed, 9 spec files`):
| mutant | result |
|---|---|
| E Camera: the stick's look computed and thrown away | killed, 4 camera-pad cases |
| F Camera: the stick looks only with the cursor free | killed, 4 camera-pad cases |
| Camera: `Pad.look(x, y, 1 / 60)` (frame-rate bound) | killed by place.spec's needle only (camera-pad steps at 1/60) |
| Camera: pitch inverted (`Pad.look(x, -y, dt)`) | killed (camera-pad pitch case, place.spec) |
| Camera: the stick's look moved after `View.steer` / after the snapshot | killed (place.spec; 5 camera-pad cases for the latter) |
| B LobbyPad: `and` → `or` | killed, 4 lobby-pad cases |
| C LobbyPad: no selection at start | killed, 1 |
| D LobbyPad: no re-select after a clear | killed, 1 |
| LobbyPad: `LastInputTypeChanged` not connected | killed, 1 |
| LobbyPad: on change, `choose(GetLastInputType())` instead of the argument | survives: equivalent (Roblox's last input type is the new one when the signal fires) |
| Sticks: no reset on a change of controller | killed, 1 sticks-pads case |
| Pads.stick: a constant `"Gamepad1"` as the controller | killed, 2 |
| Pad.track back to the NaN check only | killed (pad.spec) |
| A Pads: `elseif begun` → `else` | killed (sticks-pads trigger case) |
| Controls: `"ButtonR3"` passed on instead of `Pad.CONTINUE` | killed (touch-adapters, controls.spec, place.spec) |
| **M1 Sticks: no reset on a nil read** | **survives: 46 passed, 0 failed** (F1) |

Stub fidelity: the three stubs fire signals synchronously (Roblox defers them by default); none of the cases depends on the order of a handler against the code after the write that fired it (LobbyPad's handler re-reads the selection and returns once one is set). LobbyPad's stub fires `SelectedObject`'s change only on a real change, as Roblox does. Camera's stub reads the pitch from the last `CFrame.Angles` call, which is Camera's pitch factor. Pads' stub gives each enum item one identity, as Roblox does. The stubs load Logic by name and refuse unknown services; f0143, the one prepared issue that edits Sticks and Camera, adds only a Logic require (`Boost`) and `os.clock`, and these are executor-owned specs it may edit, so no finding. The user's decisions still hold in the code (left stick steers, right stick looks, ButtonA jumps, R2 fires, the D-pad takes the keys' path, the most recent controller drives with the 15° margin).

### F1 [medium] Sticks' reset on a nil read is pinned by no case, and the one path it alone decides sends a turn the player did not make
Where: `pickman/src/client/Sticks.luau:20-24` (`steer, source = Pad.steerStart(), nil` on a nil read); `pickman/tests/place/sticks-pads.spec.luau` (its three Sticks cases); the new lesson `pickman/skills/pickman-arch/lessons/folds-reset-when-their-source-changes.md` ("reset the fold on a nil read … the same source reconnecting at rest")
Evidence: mutant M1 (`steer, source = Pad.steerStart(), nil` → `local _ = nil`, so a nil read keeps the fold and the source) passes every case: `M1-no-nil-reset: 46 passed, 0 failed, 9 spec files`. The nil reset is redundant in the disconnect case (the other pad's reading changes `from`, which resets anyway) and invisible in the at-rest reconnect (a stick at rest releases any fold). The only path where it decides the outcome is the same controller dropping mid-push and coming back with the stick still held. A scratch case in the clone (sticks-pads' own `world()`: Gamepad1 pushed left, one beat, `connected.Gamepad1 = false`, one beat, `connected.Gamepad1 = true`, one beat, still at -0.9) printed `FIRED Left,Left` on the branch and `FIRED Left` with M1. `Left` is a relative turn (`Movement` `turn`: `Maze.left(h)`), so the branch sends a second left turn for one physical push that never let go, which the buffer turns into a real turn at the next left opening within `turnBufferTicks`. The refute's "a reset on nil reads only … fails 1" tests the other half; nothing tests this one.
Critique: the tempting fix is a case that pins `Left, Left` for the same pad reconnecting still pushed. That pins the phantom turn: a held stick sends one intent a push (`Pad.steer`'s whole rule), and a dropout the player didn't notice is not a new push. And the round-1 Recommendation that asked for "resets its fold whenever the read is nil" is where the reset came from, so the mechanism, not just the missing case, is in question: a nil read says nothing about the stick, only that it couldn't be read.
Consequences: keeping the fold across a nil read (resetting only when `from` differs from the source it came from) makes a release and a new push of the same sector, both inside one dropout, look like one held push: that push is lost and the player pushes again, the same cost as any reading the dropout hid. It also drops the per-frame `Pad.steerStart()` table that every keyboard or touch player now allocates on each Heartbeat (their read is always nil). The disconnect-then-another-pad case still turns, through the change of source. A dropout long enough to change the driver (the player uses another pad) is a change of source and resets.
Recommendation: Sticks returns on a nil read without touching `steer` or `source`, and resets only when `from ~= source`. Cases in sticks-pads (each must fail on the mutant named): the same pad drops mid-push and returns still pushed sends nothing more (fails on today's nil reset); the same pad drops mid-push, returns released, then pushed the same way, sends the turn again; the existing disconnect-then-Gamepad2 and two-pads cases stay green (they fail on "no reset on a change"). Update the Sticks comment, f0146's Sticks paragraph if it states the reset, and the new lesson's "How to apply" (a nil read is not a change of source; give each reset a case that fails without it). If the author holds that a reconnect while held should turn again, that is a product question: escalate to the user with both behaviours, and pin whichever is chosen.
Lesson: pickman-arch/folds-reset-when-their-source-changes

### F2 [low] pad.spec's non-finite case asserts `-math.huge`, which the threshold refuses without `finite`
Where: `pickman/tests/unit/Pad/pad.spec.luau:19-24`
Evidence: `-math.huge >= Pad.STEER_OFF` is false, so `Pad.track("Gamepad1", "Gamepad2", -math.huge)` returns `Gamepad1` with or without `finite`; only the `math.huge` line kills the review-001 mutant (`M5-track-nan: 45 passed, 1 failed`, the case). Harmless, but the case reads as if it pinned three refusals.
Critique / Consequences: none.
Recommendation: keep the line but say in the case name or a comment that `math.huge` is the one the threshold would let through, or drop the `-math.huge` line.

## Judged criteria (code mode only)
None: f0146 has no Judged criteria.

## Candidate lesson (for the lead to harvest)
- An amendment to pickman-arch/folds-reset-when-their-source-changes rather than a new file: "an unreadable reading is not a change of source". A fold resets when the source it reads changes identity, not when a read fails; a reset on a failed read is either redundant (the next source differs anyway) or re-emits a held push when the same source comes back. Check: for each reset of a fold, which case fails if that one reset is removed, and what does the same source coming back mid-hold send?

Verdict: changes
