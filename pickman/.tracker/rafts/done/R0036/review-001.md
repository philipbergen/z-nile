# Review 001: R0036 (code mode)
Inputs: HEAD 4104200 (`git diff origin/main...HEAD`: `tests/acceptance/f0014/keys.spec.luau`, `tracker/issues/done/f0014/f0014.md`, c0103 doc and spend, R0036 spend); R0036.md, c0103.md, c0103 `check.sh` and `acceptance/narrowed.spec.luau`, f0014 `check.sh`, f0104.md, `tracker/game-design.md` ("Desktop keys").

No findings.

Checked:
- **Design adherence**: the `keys.spec` diff is line for line `experiments/narrowing.patch` (the `+`/`-` lines of the two compared with `diff`: identical). Every row of the Design's case table is in it: five rows dropped, `n >= 4`, `Q`/`E` out of the unbound list, case 3 now checks for non-empty strings and W/A/S/D intents, the cases renamed, the "Narrowed by c0103" header added. Nothing in `src/` changed.
- **Sequestration**: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists nothing. The only promoted spec edited is `f0014/keys.spec`, which c0103's `Overrides:` line names. That is the point of the chore.
- **f0014.md note**: accurate. It says that W/A/S/D are pinned, that `w`, `Return`, `LeftShift` and `""` are unbound, that every action is a non-empty name and that the count is a floor of four. That is exactly what the narrowed spec asserts. AC5 is left as built, and `f0014/check.sh` AC5 still runs `keys.spec`.
- **Is the narrowing enough for f0104?** The spec still pins W→Forward, A→Left, D→Right, S→Back (all kept by game-design "Desktop keys" and f0104), plus `w`, `Return`, `LeftShift` and `""` unbound. f0104 binds none of those four: `Return` belongs to Flow's `PLAY_AGAIN_KEYS`, a separate table, and no backlog or active item binds Shift. Space→Jump, E→Fire and the arrows→look are all free now. A grep of `tests/acceptance` and `tests/unit` finds no other promoted spec that pins `Space`, `"Snap"`, `"Up"` or the `View.KEYS` contents. `view.spec` only checks that the map is frozen. f0014 `look.spec` pins `View.snap` (the function), which f0104 keeps on purpose. E2 recorded this map passing. Nothing found that keeps f0104 from landing green.
- **Weak tests**: the narrowed spec still has a negative case (unbound keys) and real assertions on the four kept keys. `narrowed.spec` pins it token for token, so a later weakening fails AC1.
- **Repository safety**: the diff adds no command, script or fixture. Nothing in it can write the repository.
- **Runs** (in the worktree): `scripts/tracker.sh check c0103` 3/3 PASS; `scripts/tracker.sh promote-check R0036` OK (9 passed); `scripts/check.sh --full` GATE PASSED (67.7 s).

## Judged criteria (code mode only)
None (c0103 has no Judged criteria).

Verdict: approve
