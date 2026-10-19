# Review 001: R0036 (design mode)
Inputs: branch prep-narrow-key-map at 72f6806 plus the uncommitted prep files: tracker/rafts/R0036/{R0036.md,check.sh}, tracker/issues/c0103/{c0103.md,check.sh,acceptance/narrowed.spec.luau,experiments/narrowing.patch}; also src/shared/Logic/View/init.luau, src/client/Controls.luau, tests/acceptance/f0014/*, tests/unit/View/view.spec.luau, tracker/issues/f0104/f0104.md, tracker/issues/done/f0014/check.sh. I re-ran the patch in a scratch copy (outside the repo): the narrowed keys.spec, view.spec and narrowed.spec pass, 13 cases. `tracker.sh check c0103` before the patch: AC1 fails (as it should), AC2 and AC3 pass. `promote-check R0036`: OK.

### F1 [high] AC1 passes when every assertion in the narrowed keys.spec has been made vacuous
Where: tracker/issues/c0103/acceptance/narrowed.spec.luau, cases "it keeps exactly its three cases …" and "it still pins the movement keys …"; c0103 Rules and mutants
Evidence: In a scratch copy with the patch applied, I made four edits to keys.spec: `t.expect(View.action(key)).toBe(action)` became `t.expect(View.action(key) ~= nil).toBe(true)`, the unbound-keys assertion became `t.expect(true).toBe(true)`, `""` was dropped from the list, and the intent check became `Movement.isIntent(View.action(key)) or true`. narrowed.spec still reported 4 passed, 0 failed. The case-and-count check only counts `t.expect(` calls. The kept needles (`W = "Forward"`, `"w"`, `Movement.isIntent`, `View.KEYS`, `n >= 4`) all sit in data or in surrounding code, not in the assertions. So AC1 ("still asserts W, A, S and D, the unbound keys and the shape of the map") can be met by a spec that asserts nothing, and AC2 then passes trivially. None of M1 to M7 covers a kept assertion that was weakened.
Critique: The executor is told to apply a ready patch, so the risk is small in practice. But this check is the only guard against someone "fixing" a red keys.spec later, for example f0104 under pressure, by loosening it. The tempting fix is to add a single needle for `toBe(action)`.
Consequences: Assertion needles are tied to the patch's exact formatting, and stylua runs in step 3. Each needle has to survive stylua (single-line expressions do), and narrowed.spec's header already says any later change to keys.spec must update it.
Recommendation: Add these assertion-level needles to the "still pins" case: `t.expect(View.action(key)).toBe(action)`, `t.expect(View.action(key)).toBe(nil)`, `Movement.isIntent(View.action(key))).toBe(true)` (the closing parens rule out `or true`), and `"LeftShift", ""` (the empty string stays checked). Drop `n >= 4` as a needle, or keep the floor but don't count it as "the shape": it is implied by the four W/A/S/D assertions. Add mutants M8 (the W/A/S/D assertion weakened to `~= nil`), M9 (the unbound assertion made vacuous) and M10 (`or true` on isIntent) to the Rules table, and run them on a scratch copy like E3.

### F2 [high] `tracker.sh members R0036` is empty: c0103 has `raft:` blank, so RC0 never runs c0103's checks and `ready` will refuse
Where: tracker/issues/c0103/c0103.md front matter (`raft: `); R0036.md `issues: [c0103]`; tracker/rafts/R0036/check.sh member loop
Evidence: `scripts/tracker.sh members R0036` prints nothing. The raft's check.sh runs `for dir in $(scripts/tracker.sh members R0036)`, which loops zero times, so the raft gate would pass without running AC1 to AC3. ticket-prep step 5: "check that the raft's `issues:` list names exactly the issues whose `raft:` is that raft: `tracker.sh ready` refuses a raft where they disagree".
Critique: As written, the raft can't be readied. If someone readies it by hand, its exit criteria pass vacuously.
Consequences: none beyond setting the field. `status`/`ready` key on `raft:`.
Recommendation: Set `raft: R0036` in c0103.md, then re-run `tracker.sh members R0036` and confirm it prints c0103's directory before the prep commit.

### F3 [medium] The claim "exactly this narrowing is enough for f0104" holds only if f0104 keeps `View.snap`; f0104's draft offers to remove it, which turns f0014/look.spec red
Where: c0103 Design ("`f0014/place.spec` … need nothing"), E2; tracker/issues/f0104/f0104.md Solution ("the Snap path in `Controls` and `View` is removed or retargeted"); tests/acceptance/f0014/look.spec.luau:62-64 (`View.snap({yaw=2,pitch=-1})` must be `{yaw=0,pitch=0}`)
Evidence: E2 kept `View.snap` (it only rewrote `View.KEYS` and widened `Action`). f0104 lists "removed" as an option. Deleting `View.snap` makes look.spec AC4 fail, and f0014/check.sh AC4 with it. That is a promoted spec this chore doesn't narrow and no Overrides line names. No other promoted spec pins the keys: I grepped tests/ for `View.KEYS`, `View.action`, `Snap`, `KeyCode`, `Space` and `Controls`. Only keys.spec, view.spec (frozen map, unaffected) and f0014/place.spec (Controls requires View, unaffected) hit.
Critique: The raft's whole purpose is that f0104 lands without red. The tempting fix is to also narrow look.spec here.
Consequences: Narrowing look.spec un-pins a function that f0104's springback ("on release the view springs back to the heading", "pressing an arrow snaps out of mouse look") will almost certainly reuse. The cheaper route is a recorded decision.
Recommendation: Record in c0103's Design (and as a note for f0104's prep) that `View.snap` stays: the arrow springback and the snap out of mouse look use it, and only the Snap *key action* and the `onSnap` path in Controls go. Reword f0104's Solution line to "the Snap key action is removed; `View.snap` stays (f0014 look.spec pins it)". If the user wants `View.snap` gone, then look.spec needs its own chore in f0104's `depends_on`.

### F4 [medium] f0104 says it "then overrides what is left of" keys.spec, which would also break the promoted narrowed.spec, and nothing tells it so
Where: tracker/issues/f0104/f0104.md Solution, last bullet; narrowed.spec header ("any later change to … keys.spec.luau must update the case list and the needles here")
Evidence: After c0103 is done, narrowed.spec lives in tests/acceptance/c0103/. It isn't selected by `--affected` because it reads text, so an f0104 edit to keys.spec would pass the affected gate and only fail `--full`. Its `Overrides:` line would also have to name tests/acceptance/c0103/narrowed.spec.luau. The point of c0103 is that f0104 needs no override.
Critique: This leaves two docs that disagree, and the failure only shows up late, in the full gate.
Consequences: none if f0104 doesn't touch keys.spec.
Recommendation: Change f0104's line to "c0103 narrows it first, so this issue leaves keys.spec alone. Any edit to it must also override tests/acceptance/c0103/narrowed.spec.luau." Mention this in c0103's Maintainability section.

### F5 [low] The Solution paragraph promises a Controls check that doesn't exist
Where: c0103.md Solution ("keep the checks that … `Controls` binds every key in `View.KEYS`")
Evidence: keys.spec has no such check, and the Design (rightly) doesn't add one. The only related promoted check is f0014/place.spec ("each client adapter uses the View feature").
Recommendation: Strike the Controls clause, or point it at place.spec, so an executor doesn't go looking for it.

### F6 [low] The "gone" needles are plain substrings, so `"Up"` and `"Down"` forbid any identifier containing them
Where: narrowed.spec "it no longer pins …"
Evidence: `has(src, "Up")` fails on any later code token containing `Up` (say, a helper called `lookUp`), even when it pins nothing about the arrow keys. `Left =` is evaded by `["Left"] = "Left"`.
Recommendation: Match keys with a frontier pattern, e.g. `%f[%w]Up%f[^%w]`, and the table-key forms `Up%s*=` / `%["Up"%]`. Optional, since the header already ties narrowed.spec to keys.spec edits.

Verdict: changes
