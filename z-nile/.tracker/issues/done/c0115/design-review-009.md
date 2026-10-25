# Review 009: c0115 (design mode)
Inputs: prep-c0115 at 7f0b3d2 (the delta `git diff c999297..HEAD`: the answers to round 008), with design-review-008 and design-refute-008; c0113's document, `check.sh` and capture (`./zn capture c0113`); proto-c0115 at 2956c44.
Dropped from design-review-008: none. F1 and F2 are fixed, verified below.

Verified:
- 008 F1: c0113.md has no template placeholder left (no `<!--`, no `<promoted specs …>`; the only `<!--` hit across both items' documents and `check.sh` files is the spend.md totals line). `Overrides: none`, with the reason. Checked lists AC1 and AC2 in `check.sh` order, with the same wording as the `check` lines. The Test plan maps the README case to AC1 and the `ls-files --error-unmatch` command, as `check.sh` runs it, to AC2. Of the two Rules rows, the README row's mutant (no `active --> prepared: z-stop`) is asserted literally at `readme.spec.luau:174`. Against the capture, the title, Problem, Non-goals and Solution are unchanged, apart from the `Decided with the user (2026-10-21)` line on closing it as superseded. Each of the Solution's four asks is mapped to a README section in the Design and pinned by AC1. `./zn check c0113` on the prototype: 2/2. c0113.md and both `check.sh` files are byte-identical between the prototype and this branch.
- 008 F2: `engine.copy` skips `z-nile/skills` in its `z-nile/` loop and copies each `engine.COPIED_SKILLS` folder (if it exists). `clearLessons` and the G7 case in `prompt.spec.luau` read the same list. Callers: about 20 specs and `trackerfix.luau` call `engine.copy`, and none passes a different list. With the current list `{ "z-nile/skills" }`, a root that has `z-nile/skills` gets the same copy as before, and a root without one (an older seed) gets nothing, as before, thanks to the `isDir` guard. Only the order of the copies changed, and nothing depends on it. The prototype.patch hunk for `tests/lib/engine.luau` is identical to `git diff f404e47 2956c44` of that file.
- Regressions since c999297: the delta touches only c0113.md, the c0115 log, harvest.md and prototype.patch. No `check.sh` or acceptance file changed. Harvest: the F1 and F2 entries map to existing lessons, and the round-8 note (commit before any tool that resets files) is a lesson another raft could fail.

No findings.

Verdict: approve
