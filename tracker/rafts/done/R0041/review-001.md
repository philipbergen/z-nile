# Review 001: R0041 (code mode)
Inputs: HEAD 132ac8bc3815b3e86a2f8e92656dc9a943424a10 against origin/main a4bf56d (`git diff origin/main...HEAD`: `tests/acceptance/d0105/radar.spec.luau`, `tests/acceptance/d0105/adapter.spec.luau`, c0106's document and spend, R0041's spend); R0041.md, R0041 `check.sh`, c0106.md, c0106 `check.sh`, `acceptance/narrow-radar.spec.luau`, `acceptance/narrow-adapter.spec.luau`; `src/client/DangerHud.luau`; f0029.md (the shapes the narrowing must accept).

No findings.

What was checked:
- **Correctness**: both d0105 edits are the Design snippets byte for byte (after stylua). The adapter case finds the head plainly, then anchors `^[,)][^\n]*` plus the `%p`-escaped tail on the rest, so `radarSize` must end at `,` or `)`, the rest of that one line is free, and the Position line must be the very next line. Traced by hand against today's `DangerHud.luau` line 76 (accepted), f0029's Design line `Hud.radarBox(view.X, view.Y, radarSize, UserInputService.TouchEnabled, bandTop())` (accepted; `[^\n]*` does not stop at the inner `)`), `radarSizes` (rejected), and a detached Position line (rejected). `string.gsub` inside `..` is truncated to its first result, so the pattern is a single string. The `(start :: number)` cast only runs after the `start ~= nil` expect, which throws first. `source()` strips `--` comments, and neither f0029 argument contains `--`. The radar case compares the five f0019 fields, so f0029's `safeX/safeY/safeW/safeH` are ignored and a missing field (nil) still fails `toEqual`.
- **Gate and checks**: `scripts/check.sh --full` passed (1887 passed, 0 failed, 274 spec files, 73.8s; the jail started, with no refusal). `scripts/tracker.sh check c0106` passed 3/3. I did not run the raft's `promote-check` line myself; the author's verification log records the raft `check.sh` at 3/3.
- **Sequestration**: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists nothing.
- **Weak tests**: the sequestered narrow specs load the promoted files with a fake `require` and exercise the narrowed cases against witnesses and mutants, with fingerprints for the rest of each file. The fingerprinted radar region hides the expected numbers, but the "any one of the five changes" and "missing" cases pin them behaviourally. Neither depends on the clock or randomness.
- **Design adherence**: no deviations, and `src/` is untouched. The Touched modules match the diff.
- **Regressions and overrides**: `lune run scripts/affected` on both paths selects only the two d0105 specs. `grep -rlF` for both paths outside `done/` finds only R0012's and f0029's documents and `check.sh`, plus c0106's own files. c0106's `Overrides:` line names both specs.
- **Architecture and performance**: test-only change; there's no new require edge and nothing per-frame.
- **Repository safety**: both edited specs only read the place's `DangerHud` source and call `Hud`. They make no writes and run no git or process commands, and no guard file is touched. The "Caught only by review" items (Linux unjailed writes, `check.sh` own commands) don't apply: neither `check.sh` was changed.
- **Lessons (build)**: `plain-find-for-literals` is respected (plain `find` for the head and the counts, a `%p`-escaped tail). `pin-call-site-arguments`: the first three arguments are pinned literally, and the extra ones are deliberately free per the Design (f0029's `jump.spec` pins them). `no-vacuous-pass`: the head-not-found path fails on the `start ~= nil` expect. The other lessons are about tracker tooling and don't apply.

Candidate lesson: none.

## Judged criteria (code mode only)
None.

Verdict: approve
