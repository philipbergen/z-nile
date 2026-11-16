# Review 004: f0143 (design mode)
Inputs: prep-speed-boost-escape 649523fa (f0143.md, check.sh, harvest.md, acceptance/*, the new lesson z-design/late-pins-run-on-the-merged-deps-tree; diff 36a786ec..649523fa); design-review-003 (answers in the Verification log and Order & dependencies, no refute file); local branch proto-f0143-deps2 9c6670b2, cloned to the reviewer's scratch `dr-f0143-004/p` (its f0143 `acceptance/*` and `check.sh` are byte-equal to the prep's, checked with `cmp`); origin/main d0149.md; commit 52911647; `./zn lessons --skill zz-review`.
Dropped from design-review-003: F1, F2, F3 (rulings below).

Rulings on review 003:
- **F1 (camera pin vs f0126's `hopTicks`): fixed.** place.spec:92 is now `Hop%.rise%(%s*hopped%s*,%s*shown%s*[,)]`. On the merged tree, Camera.luau:146 is `Hop.rise(hopped, shown, hopTicks)` and :145 `View.SCALE.fieldOfView + Boost.fov(boosted, shown)`, with `local shown = View.shownTick(` at :138. The `[,)]` still refuses `shownX`. Order & dependencies names f0126's change and the merged-dependencies run. Rerun here on the clone: `./zn check f0143` → 7/7, `./zn check f0146` → 6/6, `./zn check f0126` → 11/12 (only AC9, "the pins c0150 narrowed", as the log says).
- **F2 (HUD facts the Design didn't state): fixed.** §3 HUD now says `TextLabel` named `Boost`, text `>>`, created by `HudView.start`, hidden until the first `HudView.boost`, and the three `TextColor3` values; the Test plan quotes them. The prototype matches (HudView.luau:193-199, 349-359).
- **F3 (d0149 ordering): fixed.** `git show origin/main:pickman/.tracker/issues/d0149/d0149.md` → `depends_on: [d0151, f0110, f0143]`; 52911647 (#140) is on origin/main, and the doc quotes it.

Mutants run on the clone (each restored, `git status` clean after):
- Camera `Hop.rise(hopped, tick, hopTicks)` → AC3/AC4 red on place.spec's camera case.
- HudView cooling `fromRGB(255, 255, 255)` → AC3 red on hud.spec's colour case.
- Controls' swipe fold uses `keyTaps` instead of `touchTaps` → AC3/AC6 red on controls.spec's "a swipe up and a W never pair".

The new lesson (late-pins-run-on-the-merged-deps-tree) overlaps the f0143 note on z-design/run-the-other-rafts-specs, but it adds a separate rule (pin only the part of a line the issue owns) that another raft could get wrong, so it isn't a restated finding.

No findings.

Verdict: approve
