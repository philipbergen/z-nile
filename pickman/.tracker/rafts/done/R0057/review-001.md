# Review 001: R0057 (code mode)
Inputs: HEAD d64f5345 (branch R0057-narrow-key-and-hop-pins) against origin/main b01596a6 after `./zn sync --fetch`; `git diff origin/main...HEAD` (7 files); R0057.md, R0057/check.sh; c0150.md, c0150/check.sh, c0150/acceptance/narrowed.spec.luau, c0150/experiments/narrowing.patch and mutants.py; f0126's sequestered specs (for the third argument's pin).

No findings.

What I checked:
- **The change is the reviewed patch, nothing more.** The `+`/`-` lines of `git diff origin/main...HEAD -- pickman/tests` are identical to those of `experiments/narrowing.patch` (`diff` of both: no output). Nothing in `src/` changes.
- **Keeps what the Design says it keeps.** keys.spec: each of the ten bindings is checked in `View.action` and in `View.KEYS`; any key beyond the ten must bind an action that is none of the ten's (`taken`) and not a movement intent; the arrows/Space/E case and the "no Snap" loop over `View.KEYS` are unchanged, so an extra key bound to `Snap` still fails; `Q e space w Return LeftShift KeypadEnter ""` stay unbound; the frozen case is unchanged. place.spec: only `%s*%)` became `%s*[,%)]`; `[%w_]+` followed by `,` or `)` still rejects `shown.x` or `snap.tick`, the capture is still tied to `local <at> = View.shownTick(prev, snap, View.alpha(os.clock() - arrived))`, and one `camera.CFrame =`.
- **Allows only what it says.** F no longer required unbound; more keys only with actions of their own; further arguments after the shown tick. The third argument itself is not pinned here, which is the point; f0126's sequestered `views.spec.luau:631` pins `Camera.hopTicks` to `Hop.LONG_TICKS`, and `parts.spec.luau:132` pins a bad length falling back to the two-argument rise (zz-test/pin-call-site-arguments is met by the feature that adds the argument).
- **Sequestration.** `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**' '*/.tracker/**/experiments/**'` lists nothing; `git diff --summary` shows only `create mode 100644 …/R0057/spend.md`, no mode change. The two edited promoted specs are the ones c0150's `Overrides:` line names.
- **Ledgers.** f0104.md and f0101.md gain a dated "Narrowed by c0150" note above their AC sections, as c0103 did for f0014; both `check.sh` files still name the specs (narrowed.spec case 1, run).
- **Runs.** `./zn check c0150`: 3/3 PASS. `z-nile/check.sh --full`: see the last line below.
- **Repository safety.** The diff adds no script, `check.sh` or spec that writes anything; `narrowed.spec` only reads two files. No guard file touched.
- **Lessons** (`./zn lessons --when build`): split-paths-still-need-renamed-id (narrowed.spec maps both ids through `renamed.id`), plain-find-for-literals (its `string.find`s pass `plain = true`), promoted-specs-pin-rules-not-sets (the narrowing turns a set, "exactly ten", into a rule), pin-call-site-arguments (above): none repeated.

Not a finding (noted for the record): `t.expect(n >= 10)` is implied by the ten `View.KEYS[key]` checks above it, and two extra keys may share one new action; both are what the Design states, and neither lets a regression the old pins caught through.

Gate: `z-nile/check.sh --full` at d64f5345: GATE PASSED (full), pickman 1447 passed, 0 failed, 213 spec files; gate wall time 173.1s.

Verdict: approve
