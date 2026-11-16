# Review 005: f0158 (design mode)
Inputs: prep-danger-radar-ring @ 99256112 (f0158.md, check.sh, harvest.md, acceptance/{ring,clear,place,colors}.spec.luau, design-review-001..004.md, design-refute-001..004.md); prototype proto-f0158 @ 0e5a481f; today's origin/main @ fd6840af; origin/R0056-white-ghost-green-walls @ a5833978 (f0109).
Dropped from review-004: none. Both round-4 findings are fixed, checked below.

All probes ran only in a throwaway fixture, `prep-danger-radar-ring/.cache/review5-comb`, with rokit's Lune 0.10.5 (`lune --version`: lune 0.10.5). It is its own repository (origin removed): a clone of review 004's `review4-comb` (origin/main b53c95bb, origin/R0056 a5833978 merged, the prototype's `pickman/src` changes applied), with the prep's f0158 folder at 99256112 copied over and committed as `rev@example.invalid` (one `-c` commit, no config written). DangerHud, Awareness, View and Touch are byte-equal to proto-f0158 @ 0e5a481f (`cmp`), and its specs are equal to the prep's (`diff -r`). Since b53c95bb, origin/main has changed only `z-nile/next` under `pickman/src`, `pickman/tests`, `z-nile` and `tests` (`git diff --stat b53c95bb origin/main`), so the fixture's base still stands for today's main.
- `./zn check f0158`: 4/4.
- Each spec file run alone: ring 8, clear 4, place 3, colors 3 passed. This matches E1.
- The whole pickman suite (`lune run tests/run` in `pickman/`, specs copied to `tests/acceptance/f0158`, removed afterwards): `1469 passed, 5 failed, 220 spec files`. That is review 004's 1470 minus the deleted case. The five failures are exactly E3's (d0105/adapter, f0033/adapters, f0102/place ×3), and c0159 on main narrows all five.
- `./zn promote-check f0158`: OK. `bash -n check.sh`: OK. `AC_LIST=1`: `4 criteria listed (none run)`.
- `./zn capture f0158`: 0bcb8325, the one-line stub. The scope judgement from rounds 1–4 still holds, and every outcome still has a Design and a Checked criterion.

Round-4 fixes, re-run:
- F1: the source-text "own screen" case is gone (`git diff 353e6276..99256112`: −21 lines). The real-source case now compares FlowView's `DisplayOrder` with the drawn `ring.DisplayOrder` and keeps HudView's `DisplayOrder = 1` read. On the fixture, with `place.spec` through `tests/run`, each mutant failed the real-source case on its own assertion:
  - R11 (`edge.DisplayOrder = 2`): `2 passed, 1 failed`.
  - R25 (`DeviceSafeInsets`): `2 passed, 1 failed`, at `place.spec:95: expected "ScreenInsets.CoreUISafeInsets", got "ScreenInsets.DeviceSafeInsets"`.
  - R31 (`DisplayOrder = 0`): `2 passed, 1 failed`, at `place.spec:97`.
  - R34 (`edge.IgnoreGuiInset = true`): `2 passed, 1 failed`.
  - My own extras: the Danger screen at `DisplayOrder = 3` failed, and `-1` then reassigned to `5` failed.

  These correct variants pass (3/0): `gui.DisplayOrder = 0` on the Danger screen, the insets through a local, and `edge.DisplayOrder = -5`. Fixed.
- F2: E1 now says "ring 8, place 3, colors 3 and clear 4". The Regression guard says c0159's fill is on main (#169, 311cce4c), and `git log origin/main` shows `311cce4c tracker: c0159 filled (capture) (#169)`. The Test plan no longer lists the deleted case. A search for the stale forms (`grep -nE "own screen|orders\[1\]|place 4|ring 7|not yet on main|fifth"` over f0158.md and the specs) hits only the dated Verification-log lines, which are history, plus two uses of "own screen" in other senses. Fixed.

### F1 [low] Nothing pins the Ring screen's `ResetOnSpawn = false`, so a ring that disappears after a character respawn passes every check
Where: Design, "The adapter" (it names the Ring screen's `ScreenInsets`, `DisplayOrder` and `IgnoreGuiInset`, but not `ResetOnSpawn`); acceptance/place.spec.luau real-source case.
Evidence: I deleted `edge.ResetOnSpawn = false` from the prototype's DangerHud (line 68). In the fixture, ring 8/0, clear 4/0, place 3/0 and colors 3/0 all still passed. In Roblox a ScreenGui defaults to `ResetOnSpawn = true`, so the Ring screen and its 48 cached frames are destroyed when the character respawns. `DangerHud.start` runs once, so the ring would never come back. The search `grep -rn ResetOnSpawn pickman/tests` has no hits. No spec pins this for any screen (HudView, FlowView, LobbyView and the Danger screen set it untested too), so this is a project-wide gap that f0158 inherits, not one it introduces. The prototype gets it right, and the Design says the glows' screen "becomes" the ring's, which keeps the line. `grep -rn "Character" pickman/src` finds no character handling, so no respawn path is proven in today's game. That is why this is low.
Critique: an executor who writes the Ring screen fresh instead of editing the glows' screen could drop the line, and no gate would see it.
Consequences: a single `ring.ResetOnSpawn == false` assert in the real-source case is cheap. The fake engine stores the property as set, so the assert reads what the adapter set. It doesn't touch the other screens.
Recommendation: optional, and not a blocker. Name `ResetOnSpawn = false` in the Design's adapter paragraph and add `t.expect(ring.ResetOnSpawn).toBe(false)` to the place.spec real-source case: it is a rule, so it belongs in the spec. Pinning it for the other screens is a separate capture, not this issue's.

Lessons pass (`./zn lessons --when design`, every check read against the draft). Nothing fails:
- z-design/mutation-runner-runs-correct-variants: the Verification log's round-4 line records the two correct adapters, and I re-ran them plus a third.
- z-design/late-pins-run-on-the-merged-deps-tree: the HudView and FlowView order reads ran on the fixture with f0109 merged. Review 004 confirmed f0126's prototype keeps both orders, and f0126's Touched list does not include DangerHud or FlowView.
- zz-test/source-pins-name-what-the-design-names: the remaining DangerHud needles (`Awareness.ring(`, `View.DANGER_COLOR`, the absent glow and trig calls) are all named in the Design.
- zz-test/run-the-pinned-tools: Lune 0.10.5.

The round-4 harvest lines in `harvest.md` name existing lessons only, and no new lesson was added.

Final whole-design pass against the user's decisions:
- G1, the ring replaces the edge glows: place.spec's absence of `glowBox`/`edgePoint`, and E3's overrides through c0159.
- G2, one warning colour for dangerous ghosts only: ring "only dangerous ghosts", place's lit colour and `View.ghostColor(` absence, and colors.
- The 60% size: ring "numbers" and "one circle".
- G5, 35–85%: ring "real indicators" drives the real `Awareness.indicators` to closeness 1 and 0, and place pins the ramp.
- G8, centred below the top bar: the drawn Ring screen's `ScreenInsets`, `IgnoreGuiInset` and area. In clear.spec, the dots sit in the core-UI frame.
- G9 and G10, the accepted overlaps: clear.spec's ACCEPTED holds exactly the named screens and boxes, and the exactness check runs at check and done under `F0158_EXACT=1`.

Each decision has a Checked criterion that a wrong implementation fails. I found no high or medium defect.

Overrides: exactly E3's five, re-run above. c0159 is on main and in depends_on.

Repository safety: the specs only read source and run pure Logic and the fake engine. check.sh runs only `tests/run`, and `env F0158_EXACT=1` only gates an assertion. Every probe here ran in the `.cache` fixture.

Verdict: approve
