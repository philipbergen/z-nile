# Review 003: R0058 (code mode)
Inputs: 2d1aaced (R0058-console-gamepad, PR #152), `git diff origin/main...HEAD` (origin/main b53c95bb after `./zn sync --fetch`), the fix delta `git diff c7ed793c..HEAD` (c7ed793c added review-002), review-001/002, refute-001/002, harvest.md, the amended lesson `pickman/skills/pickman-arch/lessons/folds-reset-when-their-source-changes.md`, f0146.md and its check.sh and acceptance specs, R0058's check.sh.
Dropped from review-002: none withdrawn; F1 and F2 are verified fixed (runs below).
Runs (rokit's lune 0.10.5, `export PATH="$HOME/.rokit/bin:$PATH"`):
- `z-nile/check.sh --full` in the worktree: lint 0 errors, 0 parse errors; pickman `1467 passed, 0 failed, 217 spec files`; z-nile `1232 passed, 0 failed, 179 spec files`; `GATE PASSED (full)`, exit 0.
- `./zn check f0146`: `6/6 criteria passed`. `./zn check R0058`: `3/3 criteria passed`.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` prints nothing; `git diff --summary origin/main...HEAD` holds no `mode change`.

Mutants: in a `--no-hardlinks` clone of 2d1aaced in the reviewer's scratch folder, one substitution at a time in `src/client/Sticks.luau`, against camera-pad, lobby-pad, sticks-pads, touch-adapters, `tests/unit/Pad/pad.spec.luau` and f0146's four acceptance specs (baseline `48 passed, 0 failed, 9 spec files`):
| mutant | result |
|---|---|
| M1 round 001's nil reset back (`steer, source = Pad.steerStart(), nil` before the `return`) | killed: 1, "the same pad dropping mid-push and returning still pushed sends nothing more" |
| M3 a nil read clears only `source` | killed: the same case |
| M4 a nil read resets only the fold | killed: the same case |
| M2 no reset on a change of controller | killed: 2 ("a disconnect mid-push…", "two connected pads…") |
| M5 reset on a change, `source` never updated (resets every frame) | killed: 3 (two controls.spec, one sticks-pads) |
| M6 `from ~= source and from ~= nil` | survives: equivalent (`from` is nil only with `x`, `y` nil, which returned above) |

Review-002 F1's scenario re-run: on M1 the same-pad-returns-held case now fails, on the branch it passes, so the phantom second turn is gone and pinned. Review-002 F2: `pad.spec`'s case now holds `math.huge`, NaN and 1 only, and is named for the one the threshold would let through.

Whole diff, looked at again: Camera, Controls, FlowView, both Mains, LobbyPad, Pads, Logic/Pad, fakeengine and architecture.md are unchanged since review-002's approval of them. The user's decisions still hold: the left stick steers (Sticks, `Pad.steer`), the right stick looks (Camera, `Pad.look`), the jump button (`ButtonA`), R2 fires, the D-pad takes the keys' path (Controls through `Pad.action`), and the most recent controller drives with the 15° margin (`Pad.track`, `Pad.STEER_MARGIN`). The fix's own consequence (a release and a new push both inside one dropout read as one held push) is the trade-off review-002 named and the refute accepts; Pads reads the pad every Heartbeat once it is connected again, so it needs a push already in progress at the first frame after reconnection, which no finding is raised for. Repository safety: the delta touches one adapter, two specs and a lesson; no script, no `check.sh`, no git, no file write.

### F1 [low] sticks-pads.spec's header and its first case's name still say a disconnect resets the fold
Where: `pickman/tests/place/sticks-pads.spec.luau:2-4` ("a read of nothing (a disconnect) and a change of driving controller both reset it") and `:143` ("a disconnect mid-push resets the fold: the other pad's first push the same way turns")
Evidence: since cc4930c3, a nil read keeps the fold (`Sticks.luau:20-24`), and the spec's own new case says so. The first case is green only through the change of controller (M2 kills it, M1/M3/M4 don't). Search: `git grep -nE -i 'read of nothing|nil read|disconnect.*reset|reset.*disconnect|starts afresh' -- pickman/src pickman/tests pickman/skills pickman/.tracker/issues/active/f0146 pickman/.tracker/game-design.md pickman/.tracker/architecture.md` turns up the header at `sticks-pads.spec.luau:3`, the case at `:143`, f0146.md:275 (corrected by :276, a history line, so left alone), the lesson (correct), and camera-pad.spec:4/:174 (Camera's look, which has no fold: correct).
Critique / Consequences: none. The comment and title no longer match the code they cover, and the next reader may put the nil reset back "to match".
Recommendation: reword the header ("a change of driving controller resets it; a read of nothing (a dropout) keeps it, so the same pad coming back still held sends nothing more") and the case title ("a disconnect, then the other pad pushed the same way: the change of controller resets the fold and it turns").

## Judged criteria (code mode only)
None: f0146 has no Judged criteria.

Verdict: approve
