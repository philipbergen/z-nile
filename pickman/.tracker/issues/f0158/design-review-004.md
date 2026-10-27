# Review 004: f0158 (design mode)
Inputs: prep-danger-radar-ring @ 77fb9eb8 (f0158.md, check.sh, harvest.md, acceptance/{ring,clear,place,colors}.spec.luau, design-review-001..003.md, design-refute-001..003.md, z-nile/skills/zz-test/lessons/feed-the-real-producers-extremes.md); prototype proto-f0158 @ 93335c11; today's origin/main @ b53c95bb; origin/R0056-white-ghost-green-walls @ a5833978 (f0109); origin/main's c0159 and f0126 documents; local proto-wall-picks-base3 @ 2396ce82 (f0126's prototype, unchanged since the design measured it).
Dropped from review-003: none. Every round-3 finding is fixed, checked below.

All probes ran only in a throwaway fixture, `prep-danger-radar-ring/.cache/review4-comb`, with rokit's Lune 0.10.5 (`lune --version`: 0.10.5). It is its own repository: a clone at today's origin/main b53c95bb, with origin/R0056 @ a5833978 merged (clean), then the prototype's own `pickman/src` changes applied (`24185099..557f95a7^1`, `557f95a7..d9eb585c`, `c30f9b78..93335c11`: DangerHud, Awareness, View, and f0126's `pickRect` copy in Touch). All four files are byte-equal to proto-f0158's (`cmp`). The prep's whole f0158 folder is copied into `pickman/.tracker/issues/f0158` and committed in the fixture. The fixture's `rev@example.invalid` identity was set for that one commit and then unset. With it set, the first `./zn check` refused on the fixture's own identity, which is the guard working on the fixture, not the real repository.
- `./zn check f0158`: 4/4.
- Every spec in `pickman/tests`, with the specs copied to `tests/acceptance/f0158`: `1470 passed, 5 failed, 220 spec files`. The five are exactly E3's (d0105/adapter, f0033/adapters, f0102/place ×3), and main's c0159 names all five.
- z-nile's `tests/tooling/repo-fence.spec.luau`: 10/10 (it scans every check.sh, this one's `env F0158_EXACT=1` included). `tests/acceptance/c0120/check-paths.spec.luau`: 4/4.
- `./zn promote-check f0158`: OK.
- `bash -n check.sh`: OK. `AC_LIST=1`: `4 criteria listed (none run)`.

Round-3 fixes, re-run:
- F1: R33 (`closeness = math.clamp(g.brightness, 0, 1)`, the old prototype) fails two ring cases, "only dangerous ghosts … closeness … clamped" and "fed by the real Awareness.indicators …". ring has 8 cases and place 4. The real-indicators case looks for a tile where `pathDistance(…, 12) == 12` and asserts closeness 0 there and 1 on the player's tile, so G5's 35% and 85% are both reached. Fixed.
- F2: the real-source case reads the drawn `Ring` screen (`ScreenInsets`, `IgnoreGuiInset`, `DisplayOrder < 0`, and the `Danger` screen's nil or 0). Fixed, but see F1 below.
- F3, the jail pass-through: I wrote a probe spec that only errors with `PICKMAN_TEST_JAIL` and `F0158_EXACT`, and ran it through `tests/run`. With the variable set it printed `JAIL=sandbox-exec EXACT=1`; without it, `JAIL=sandbox-exec EXACT=nil`. So the variable reaches the jailed spec. Then I made FIRE 12 px smaller (`local side = hop.w - 12` in `Touch.fireRect`). `./zn check f0158` gave `FAIL AC2 … old phone, landscape, under a 58 px top bar: fire is accepted but no ring dot overlaps it`, `3/4`. The plain run, `lune run tests/run -- …/clear.spec.luau` (the promoted gate's form), gave `4 passed, 0 failed`. Fixed as the refute says.
- F4: `lune run z-nile/affected -- pickman/src/shared/Logic/Awareness pickman/src/shared/Logic/View pickman/src/client/DangerHud.luau` in the fixture prints 77 files. Compared with every `tests/…spec.luau` path in f0158.md by `comm -3`, the difference is empty. Fixed.

### F1 [medium] place.spec's "own screen" case still pins DangerHud's text for what the drawn case now checks, so two correct adapters fail the promoted spec
Where: acceptance/place.spec.luau "the ring has its own screen, the core-UI safe area below the top bar (the HUD's frame), under the HUD": its `%.ScreenInsets%s*=%s*Enum%.ScreenInsets%.CoreUISafeInsets` needle and `#orders == 1` (exactly one `DisplayOrder = <n>` in DangerHud's source). Compare the real-source case, which since round 3 asserts the drawn `Ring` screen's `ScreenInsets`, `IgnoreGuiInset` and `DisplayOrder < 0`, and allows the `Danger` screen's `DisplayOrder == 0`.
Evidence: in `review4-comb` I ran two correct variants of the prototype's DangerHud.
- `gui.DisplayOrder = 0` added to the `Danger` screen, the radar's default made explicit, which the real-source case allows in so many words.
- `local insets = Enum.ScreenInsets.CoreUISafeInsets; edge.ScreenInsets = insets`.
Each gives place `3 passed, 1 failed`, `FAIL … the ring has its own screen …`. The real-source case passes both. The case's mutants (R25 the wrong insets, R11 DisplayOrder 2, R31 DisplayOrder 0) are all killed by the drawn asserts in the real-source case already.
Critique: zz-test/source-pins-name-what-the-design-names asks: "once a behaviour case covers what a pin guarded, is the pin (an absence pin above all) deleted, since it then only forbids correct idioms?" Round 3 F2's Consequences said this needle could move to the drawn screen. The drawn asserts were added, but the needles stayed. The two cases now disagree about `Danger.DisplayOrder = 0`. Once promoted, a later DangerHud change that makes the radar's order explicit has to override f0158's spec. The tempting fix is to loosen the pattern (`#orders <= 2`). That still pins spelling.
Consequences: the case also compares FlowView's and HudView's orders with `orders[1]`, the ring's order read from text. Without the DangerHud needles, it needs the ring's drawn `DisplayOrder`. The real-source case has that value, but the other case does not run DangerHud. Rows R11, R25 and R31 then point at the real-source case. FlowView's and HudView's own source reads stay, since those screens aren't built here (round 3 asked to keep them).
Recommendation: delete the two DangerHud source reads, the `ScreenInsets` needle and the `DisplayOrder` gmatch. Move the FlowView and HudView comparisons into the real-source case, against the drawn value: `flow == nil or tonumber(flow) > ring.DisplayOrder`, and HudView's `DisplayOrder = 1` read with `ring.DisplayOrder < 1`. Then drop the "own screen" case, or keep it only for the Flow and HUD reads. Point the Rules rows for R11, R25 and R31 at "place :: real source" and re-run those three mutants. Add the two correct variants above to E2 as variants that must stay green. This is a spec change, not a check.sh one: it pins rules (zz-review/recommendations-pick-spec-or-check).
Lesson: zz-test/source-pins-name-what-the-design-names

### F2 [low] Two places still state the round-2 state
Where: f0158.md E1 ("ring 7, place 4 and colors 3 pass"); Regression guard ("c0159 … its filled text, not yet on main, must add the fifth, G8's screen case").
Evidence: ring.spec has 8 cases (the Verification log's round-3 line says so: "ring 8"). `git show origin/main:pickman/.tracker/issues/c0159/c0159.md` already lists all five cases, the fifth included ("the glows have their own screen, in the device's safe area … (its `ScreenInsets = DeviceSafeInsets` needle …)").
Critique: an executor reading the Regression guard would wait for, or try to make, a c0159 change that is already on main.
Consequences: none.
Recommendation: E1: "ring 8". Regression guard: "c0159 (filled on main, naming all five) lands first".
Lesson: z-design/restated-rules-move-together

Lessons pass (`./zn lessons --when design`, all 131 checks read against the draft). F1 repeats zz-test/source-pins-name-what-the-design-names, and F2 repeats z-design/restated-rules-move-together. Nothing else applies that the draft fails:
- zz-test/sequestered-edits-parse-and-list: `bash -n` and AC_LIST, above.
- zz-test/fixed-lines-run-their-whole-criterion: `./zn check` 4/4.
- zz-test/specs-set-host-markers-explicitly: F0158_EXACT isn't a host marker. On Linux the unjailed runner inherits the environment anyway.
- z-design/quote-other-preps-before-promising: I reran `git worktree list` and diffed every local prototype and raft branch against main over DangerHud, Awareness, Touch, Hud, HudView, FlowView and View. R0058, f0143b, f0146 and f0126's prototype touch FlowView and HudView, and each keeps FlowView's `DisplayOrder = 0` and HudView's `DisplayOrder = 1`, which place.spec reads. f0126's `pickRect` at 2396ce82 is the copy the design measured.

The author's new lesson, zz-test/feed-the-real-producers-extremes, is a general rule another raft could break (a producer's floor or cap narrowing a range the user decided), not a restated finding.

Scope fidelity: `./zn capture f0158` gives 0bcb8325, the one-line stub: "A more visible danger radar: circle segments with a ring of translucent indicators, about 60% of the smallest screen dimension". The Problem restores the user's fuller words, and G1–G10 are `Decided with the user` lines. Every outcome has a Design and a criterion: the ring (AC1, AC3), the size (AC1, AC2), the walls by f0109 (a depends_on, a Non-goal for the rule itself), and every input (display only).

Overrides: exactly E3's five, named by c0159 on main, which is in depends_on.

Repository safety: the specs only read source and pure Logic. check.sh runs only `tests/run`. `env F0158_EXACT=1` sets one variable that only gates an assertion, it's not a guard name, and repo-fence passes.

Verdict: changes
