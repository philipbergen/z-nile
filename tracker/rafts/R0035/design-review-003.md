# Review 003: R0035 (design mode)
Inputs: prep-ghost-hunter-tools at fbcd957. I reviewed the fix delta (`git diff 827e990..HEAD`: game-design, f0100, mutants.py) and the whole raft again: R0035.md, R0035/check.sh, the experiments, the f0100/f0101/f0102/f0104 documents, check.sh files and acceptance specs, and the f0110 stub. Also read: tracker/game-design.md; design-review-001/002 and design-refute-001/002; R0012 in prep-mobile-controls (still b531210, unchanged since round 2, read only); the prototype's `src/client/BlastView.luau`, `Camera.luau`, `Main.client.luau`, `View.interpolate`/`View.alpha`/`View.beamEnd` and `Session.shoot` in proto-ghost-hunter-tools (c08d562, read only, `git status` clean). The delta changes no spec, `check.sh` or `src/` file, so round 2's runs (19 acceptance specs green, full gate green, 94 mutants killed) still hold, and I did not repeat them.
Dropped from review-002: F1, F2, F3

Rulings on design-refute-002:
- F1 (answered by option (a), holds). The limitation is now stated in f0100's Design and in game-design's (prep) line. The grace is listed in Open decisions, and OC2 measures it on Beta. No rule changed, so no spec or mutant was needed. See F1 below for a related hole in what the beam shows.
- F2 (fixed, holds). ROOT is now required. A main checkout is refused: in a main checkout `--git-dir` and `--git-common-dir` are both `.git`, so they are equal; a non-repository gives two empty strings, which `realpath` turns into the same cwd, so it is refused too. A file with uncommitted changes is skipped. The restore writes the saved text back in `finally`. A worktree checkout still gets mutants written into its `src/` while the spec runs, but it is restored. That is the script's purpose, and the usage line names a scratch worktree.
- F3 (fixed, holds). The four questions are in game-design's Open decisions, and E4's count is corrected. Two stale lines remain elsewhere (F2 below).

### F1 [medium] The beam is drawn from the client's render pose, not from the tile the server shot from, so at a junction it can show a hit as a short beam into the wall, or a miss as a beam up the corridor through the ghost
Where: f0100 Design, BlastView ("draws … a `Part` from the pose to `View.beamEnd(maze, pose, frame.shot.heading)`"); `Session.Shot = { tick, heading }` (no origin); prototype `BlastView.push` (`local p = getPose()` → `View.beamEnd(m, p.x, p.y, heading)`); f0100 Usability ("the beam shows where it went"); OC2.
Evidence:
- The server's line starts at `Movement.occupied(s.maze, member.move)`: the pre-move tile, rounded at half a tile.
- The beam starts at `floor(pose + 0.5)`. That pose is Camera's `current`, which the last render step set from `View.interpolate(prev, latest, alpha)` before this frame's `Camera.push`. With frames arriving steadily, that pose is about the previous snapshot, which is the server's pre-move position, within one render frame (a quarter of a step). With jitter it is a full step or more behind. For example, when two frames reach the client between render steps, `current` still comes from two snapshots back.
- Whenever the two positions fall on different sides of a half-tile boundary, the beam starts on a different tile from the shot. At a junction with an open side corridor N:
  - The server holds the junction tile and the pose still rounds to the tile before it. The ghost up the corridor turns to eyes, and the beam runs N half a tile, into the wall at the player's side (`beamEnd` returns that tile's far edge).
  - The server already holds the tile after the junction, and the pose still rounds to the junction. The shot hits the wall, the shot is spent and the ghost is unharmed. The beam is drawn up the corridor straight through that ghost.
- The design now tells the player to press "about half a tile before the junction's centre as seen" (review 002 F1). That puts the fires right at those boundaries. At later levels and under the power's speed boost, a step covers more units, so the gap in studs grows.
- OC2 asks the tester to judge "whether the shot goes up the corridor rather than into the wall". The beam is the only thing the tester sees of the shot, apart from a ghost turning to eyes when there is one.
Critique: review 001 F3 moved the beam's *when* onto server authority (`Frame.shot.tick`). Its *where* is still guessed on the client from a pose that is, by construction, up to a few steps away from the server's position. Pillar 3 (fair and readable) is broken exactly in the case this raft has worked on for two rounds. The tempting fix is to read the pose from the new `frame.player` instead of `Camera.pose`. That is the post-move position, the wrong tile in the other direction (it is what S12 kills on the server).
Consequences:
- `Session.Shot` gains `from: Maze.Tile`, a fresh copy of the occupied tile `shoot` used. It is plain JSON data on a field that is already new, so `f0018/frame` allows it. It is still prep, so `shots.spec` can change.
- The beam then starts at that tile's centre, so it can begin up to half a tile from the eye, and off to one side of it when the eye's cross-axis coordinate is mid-tile. That is accurate, and fine for a 0.15 s flash. Say so in the Design.
- `View.beamEnd`'s signature can stay (x, y = the `from` tile). Its "the cross axis keeps the player's coordinate" rule then gives the tile's centre line.
- No new remote or server change, so RC2 is unaffected.
Recommendation:
- Add `from` to `Session.Shot` and set it in `shoot` from `Movement.occupied` before the move, a fresh table.
- BlastView draws from `frame.shot.from` to `View.beamEnd(m, from.x, from.y, heading)` and does not read the pose for the beam's line. It may still read the pose for the beam's height, or not at all.
- Specs:
  - In `shots.spec :: a moving player shoots from the tile it holds before this step's move`, assert `frame.shot.from` equals the pre-move occupied tile (12,23 in that case), not the tile the player then holds (11).
  - In `shots.spec :: the frame names the latest shot …`, assert that `from` is a fresh table.
  - In `place.spec`, pin `shot.from` in BlastView's `View.beamEnd(` call, and pin that the beam's line does not use `getPose`/`Camera.pose`.
- Rules rows and their mutants: `from` taken after `Movement.step`; `from` not copied (aliasing `member.move.tile`); BlastView using the pose. Run them in `mutants.py`.
- Update OC2: "the beam starts from the tile the server shot from".

### F2 [low] Two raft-level lines are stale after the fixes
Where: R0035 Theme ("One new open decision: the drop chance (`Blaster.DROP_PERCENT`)"); R0035 Experiments table, row E6 ("`DisplayOrder` 0 under the HUD's 1"); f0102 Unknowns E6 ("a `ScreenGui` with `DisplayOrder` 0 draws under one with 1").
Evidence: game-design's Open decisions now lists five R0035-related questions (the drop chance, the junction grace, the drop seed, the bars on touch, Inky's colour). f0102's Design and `place.spec` set the Glows to `DisplayOrder = -1`, under the Danger and Flow guis (0) and the HUD (1) (review 001 F5). So E6's engine assumption is now "a negative order draws under 0", not "0 under 1".
Critique: an executor who reads the raft first gets the wrong list of what is awaiting the user, and the wrong engine fact to check in OC1.
Consequences: none.
Recommendation:
- In the Theme, point to game-design's Open decisions for the five questions.
- Restate E6, in both places, as "a ScreenGui with a negative `DisplayOrder` draws under ones with 0 and 1".

Verdict: changes
