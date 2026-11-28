# Review 001: R0140 (code mode)
Inputs: `origin/main` (`6b7b2e030`)..HEAD (`c73ad2d3c`, branch `R0140/1/f0203`); `git diff origin/main...HEAD`; `arcade/.tracker/rafts/active/R0140/R0140.md`, `check.sh`; `arcade/.tracker/issues/active/f0203/f0203.md`, `check.sh`, `acceptance/{rng,pad,touch,look,games,place,docs}.spec.luau`, `acceptance/watch.txt`, `results.txt`, `design-review-001.md`, `design-refute-001.md`, `harvest.md`; `arcade/src/shared/Logic/{Rng,Pad,Touch,Look}/init.luau`; `arcade/tests/unit/{Rng,Pad,Touch,Look}/*.spec.luau` and `*.watch.txt`; `arcade/.tracker/architecture.md`; `arcade/skills/arcade-arch/SKILL.md`.
Checks run: `./zn check f0203` (8/8 ACs PASS); `z-nile/check.sh --affected` (PASS, 11 passed across 4 unit spec files, stylua/selene/luau-lsp/rojo clean); `bash arcade/.tracker/rafts/active/R0140/check.sh` (3/3 PASS); `./zn promote-check R0140` (OK); `arcade` `tests/meta/{architecture,home,fence}.spec.luau` + `tests/place/library.spec.luau` (25 passed, 0 failed); `pickman`, `portal`, `snake`, `invaders`, and `asteroids` `tests/place/library.spec.luau` (2 passed, 0 failed each); `z-nile/tests/acceptance/c0183/designs.spec.luau` (1 passed, 0 failed); `lune run z-nile/watch-check`, `./zn audit`, `./zn skills --check`, and `./zn guesses R0140` (all clean).
Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists only `A	arcade/.tracker/issues/active/f0203/acceptance/watch.txt`, which lists the four new source files of this layer and is the generated watch file written by `./zn finish` (`zz-review/lessons/finish-watch-is-generated.md`); no `.spec.luau`, `check.sh`, or file mode was changed.

### F1 [low] `Look` unit spec case title claims to test yielding to other look input, but its body never sends any
Where: `arcade/tests/unit/Look/look.spec.luau:13-24`
Evidence: The case is named `"springs back after arrow look and yields to other look input"`, yet the body only presses `"left"`, runs `Look.spring` for `0.12` s, releases `"left"`, and runs `Look.spring` for `0.12` s back to `yaw = 0`. No `Look.mouse`, `Look.turn`, or modified `look` argument is passed during the spring.
Critique: While AC4 (`arcade/.tracker/issues/active/f0203/acceptance/look.spec.luau:161-171`) already covers yielding during a spring and protects against regressions once promoted, this unit spec gives a false signal if run alone or read as coverage of that rule. The author may be tempted to rename the test only.
Consequences: none — adding a mid-spring `Look.mouse` call (or trimming the case title) affects only this unit spec and keeps all existing specs green.
Recommendation: Add a step in this case (or a dedicated unit case) that applies `Look.mouse(s.look, ...)` while `s.spring` is `true`, passes it to `Look.spring`, and asserts `s.spring == false` and that `s.look` preserves the mouse step; or remove `"and yields to other look input"` from the case title.
Erred: zz-execute
Upstream: none

## Judged criteria (code mode only)
- None (`f0203` Judged: None).

Verdict: approve
