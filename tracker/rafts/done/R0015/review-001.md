# Review 001: R0015 (code mode)
Inputs: branch R0015-presentation at 1b331ed against origin/main 27feded (`git diff origin/main...HEAD`); R0015.md and its check.sh; f0030, f0019 and f0031 (documents, check.sh files, acceptance specs). Runs: `scripts/check.sh --full` passed on the second run (775 specs, 22.3 s). The first run had one failure, in `tests/acceptance/c0038/deferred.spec.luau :: cleans up` ("Directory not empty"), which this diff doesn't touch. That spec passed alone and in the rerun, so it's a pre-existing flake and not a finding against this raft. `tracker.sh check` passed f0030 5/5, f0019 4/4 and f0031 5/5. RC1, RC2 and `promote-check R0015` also passed. Sequestration: `git diff 3bc4329 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty.

Areas checked with no finding:
- **Wire format**: encode and decode use the same row-major slot order and the same tile index (`y*width+x+1`) as `Pellets.new`/`fill`. A remainder character is written, the padding stays 0, and an empty maze gives `""` both ways. The client decodes against `Maze.layout(frame.maze)`, which is the same layout as the server's.
- **Play again**: the handler's only parameter is the sending `Player`, which picks both the session and the id. Logic refuses outside `gameover`. A spam after a success hits `ready` and is refused. The client's `live` gate is cosmetic only.
- **Engine adapters**:
  - The render step at Camera+1 still writes `MouseBehavior` last, after the PlayerModule.
  - CAS binds only `Return`/`KeypadEnter` at default priority and returns `Pass`. Controls sinks only its nine keys.
  - The fade Frame isn't `Active`, so it doesn't swallow clicks or touches, and the button is a later sibling.
  - Every `start()` runs before `ready:FireServer()`, and every `show` guards against nil.
  - Pellets are parented under the maze model, and `MazeView.flash` filters on `Wall`.
- **Per-frame cost**: the client does O(1) Logic work and GUI writes at 15 Hz. It decodes only when the code changes, recolours walls only on flash edges, and makes 4 `Size` writes per render frame for the pulse. The server does one 41-character encode per player per step.

### F1 [low] Main's rules fall back to `Game.CLASSIC_CONFIG`, a deviation from the design that the logs don't record
Where: src/client/Main.client.luau:16 (`local RULES = (Session.GAME_CONFIG.play or Game.CLASSIC_CONFIG) :: Game.Config`). The f0031 and f0030 Verification logs both say "No design deviations".
Evidence: The f0031 Design says `RULES = Session.GAME_CONFIG.play (cast to Game.Config)`, and it gives the reason: "the same table the server's sessions use … so the two can't disagree". The fallback (and the extra `Game` require in Main) only matters when `GAME_CONFIG.play` is nil. In that case the server runs with no pauses (`Session.new` leaves `play` absent), while the client times its fade to the classic 45-tick dying pause. That is exactly the disagreement the design rules out, and it would happen silently.
Critique: It's harmless today, because `GAME_CONFIG` is frozen with `play = Game.CLASSIC_CONFIG`. But it's a silent masking default where the design wanted the two sides to be one table. The tempting fix is to delete `or Game.CLASSIC_CONFIG` and keep the cast, which hides the optional type instead of checking it.
Consequences: Without the fallback, a nil `play` needs a loud failure at client boot, not a nil `rules` crash in `Flow.overlay` on the first frame. Main's `Game` require then only serves the type cast.
Recommendation: Use `local RULES = assert(Session.GAME_CONFIG.play, "client: Session.GAME_CONFIG has no play rules")`. That keeps the `Session.GAME_CONFIG` text the f0031 place spec reads, and keeps `Game` only for the `Game.Config` type. Alternatively, keep the fallback and record it as a deviation, with its reason, in the f0031 Verification log. No spec change is needed either way.

### F2 [low] The HUD and Flow ScreenGuis share `DisplayOrder` 0, so whether the fade darkens the HUD is left to the engine
Where: src/client/HudView.luau `HudView.start` (ScreenGui "Hud"), src/client/FlowView.luau `FlowView.start` (ScreenGui "Flow"). Neither sets `DisplayOrder`.
Evidence: Roblox doesn't define the draw order of sibling ScreenGuis with equal `DisplayOrder`. At game over and through each dying pause, the 0.6 black `Fade` frame may draw over the score, lives and power bar, or under them, and the result can differ from session to session. The f0031 design's player story ("the fade makes a death unmistakable"; game over "shows the result") doesn't say which is intended, and OC1 doesn't look for it.
Critique: It's a readability detail (Pillar 3), and an inconsistent look is the kind of thing a Studio check catches once and then misses. The tempting fix is to give the HUD a higher `DisplayOrder` without deciding what the fade is for.
Consequences: If the HUD stays above the fade, the lives disc dropping during a death stays fully legible, which is a plus. If the fade covers it, the dimmed HUD at game over makes the GAME OVER detail line the only bright score. Either way it's one adapter property, and f0029's mobile layout will inherit the choice.
Recommendation: Set `gui.DisplayOrder` explicitly in both adapters. The suggested values are Hud 1 above Flow 0, so the HUD stays readable through the fade and the PLAY AGAIN button stays on top in its own gui. Add a sentence to the f0031 Verification log that OC1 step 2 should show the HUD above the fade. Nothing Lune-checkable is needed.

## Judged criteria (code mode only)
- None. R0015, f0030, f0019 and f0031 have no Judged criteria (each issue's Judged section says "None").

Verdict: approve
