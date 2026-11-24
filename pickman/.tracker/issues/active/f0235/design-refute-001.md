# Design refute 001: f0235 (answers design-review-001)

- F1: fixed: the eye is no longer read back from `camera.CFrame`. Camera keeps one module-level `eye`. The render step computes the sum as `local drawn = View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks)`, then sets `eye = drawn` and `camera.CFrame = CFrame.new(x, drawn, z) * ...`, and `Camera.eye()` returns `eye`. This is the eye sum `f0234.md` offers. The camera-pad stub change is dropped from the Design, Touched modules, the steps and the Regression guard, and "Why the drawn eye" is rewritten as "When: the eye the camera draws", with a "With f0234" paragraph that quotes f0234's line (prep branch 40365ef0). AC4's read-back text case is gone, replaced by F2's behavioural spec. New E5 ran both landing orders on a `/tmp` scratch clone with both issues' acceptance specs:
  - Each order conflicts in `Camera.luau` on the eye line only, so git forces the merge.
  - Resolved as the Design says, both orders pass every spec of both issues, plus f0101/place, f0126/adapters and views, camera-pad, f0109/docs and f0146/place.
  - Resolved the wrong way (f0234's `local eye`), f0235's camera.spec fails 4 of 6, and that spec holds f0234's executor once f0235 is done.
  - No `depends_on` is needed, and f0234's document needs no new line, because the promoted behavioural spec carries the constraint. Rows S1, S2, S4 and M20 were added and run.
  - Consequences: camera-pad stays untouched. The f0101, f0126 and f0143 literals still match, since the sum is unchanged and so are `local shown` and the one CFrame write. f0234's sequestered camera.spec passes 6/6 on both merges.
- F2: fixed: new `acceptance/camera.spec.luau`, under AC4, runs the real Camera on a stub engine whose `CFrame.new` records the height of each frame. It has six cases:
  - nil before a snapshot;
  - the standing height;
  - `eyeHeight + Hop.RISE` at a hop's top, elevated;
  - every step of a hop and a long hop equal to the drawn height (the long hop passes rises between the clearance and the wall height, which kills S2);
  - standing again after landing;
  - `Camera.pose()` as the drawn place.

  `place.spec` keeps only Main's wiring and PelletView's getters (pickman-arch's no-camera rule). Consequences: AC4 runs two specs. S1 (a `local` shadow), S2 (the rise stored), S4 (the eye set before the sum) and M20 are each killed on an assertion (E4).
- F3: fixed: new case `pellets :: the beacons keep View.beacon's size and place every frame: they do not pulse`. It renders at a jump's top at four clock times through a pulse, and asserts each beacon's size and height against `View.beacon` and that it is lit. The Design states that beacons are not added to `h.power`. Row S3 was added, run and killed. Consequences: none.
- F4: fixed: a beacon within `View.BEACON.clear = 1.5` tiles (12 studs) of the eye's place is not shown. The comparison is strict, and a nil pose is near nothing.
  - The interface becomes `View.beacons(slots, present, elevated, pose: Pose?)` and `PelletView.start(eye, pose)`, and Main passes `Camera.eye, Camera.pose`. PelletView now writes a beacon only when its own state changes (`h.shown[i]`), which replaces the string key, so the pose's per-frame motion writes nothing until a beacon actually turns.
  - New cases: rule (near and far, the strict edge diagonally and along an axis, nil pose); pellets (a pose walking a corridor through a power pellet hides then relights it; exactly `clear` away shows and a hair nearer hides; a moving far pose writes nothing); place (Main passes `Camera.pose`; both getters are called).
  - New rows: N1 (clearance ignored), N2 (`<=`), N3 (nil pose near everything), M15 (the adapter passes no pose) and N4 (Main passes no pose), all run and killed. The game-design bullet, AC2, AC3, AC6 (`1.5 tiles`), OC1 (hop through a power pellet) and the Usability and Edge cases text say it.
  - Consequences: a hysteresis check for the new ring: no tile centre is 1.5 tiles from another, so a player at rest never sits on it (Edge cases). The distance is plain, not wrapped, because beacons have no tunnel-margin copies. The per-frame cost is now one walk of the slots, about 244 on classic (Scalability). f0234's wait is at the spawn, far from every power pellet. This is a **(prep)** choice the user may veto.
- F5: fixed: the selector was rerun with the file paths (`.../View/init.luau`). It gives 241 specs, pasted in Affected specs, which says why. Touched modules now names `pickman/.tracker/architecture.md` instead of the camera-pad spec. Consequences: none (E3's full run already covered the 20).
- F6: fixed: the bullet (in `experiments/records.patch`) now says "from about 5% of the (tile, power pellet) pairs" and "f0236's glow over the regular pellets must be clearly distinct from it", in the capture's words. `docs.spec` checks "clearly distinct". Consequences: none.
- F7: fixed: architecture.md's View row gains "; the power pellets' beacons, the raised-eye rule and the beacons' clearance (f0235)". It is in `experiments/records.patch`, Touched modules and step 6, and AC6's new case `docs :: architecture.md's View row names the beacons` (row D3) pins it. Consequences: the records patch also changes architecture.md, and E5 shows it merges clean with f0234's Hop row edit.
- F8: fixed: E1, E3, E4 and E5 now record their bounded commands. `mutants.py`'s header gives its `./zn run --time 900 -- ...` line and the patches it needs. Consequences: none.

Harvest: `harvest.md` (two new lessons: pickman-arch/new-parts-meet-the-eyes-path and z-design/affected-takes-file-paths; sharpened checks: z-design/quote-other-preps-before-promising and z-design/instructions-runnable-where-they-run).
