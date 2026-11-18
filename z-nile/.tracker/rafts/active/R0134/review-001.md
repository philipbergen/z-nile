# Review 001: R0134 (code mode)
Inputs: layer `R0134/1/d0406` at 4a735b14b, diff `git diff R0133/3/c0411...HEAD` (merge-base d603b1323, R0133's c0411 layer; R0133's own spec edits not reviewed); z-nile/engine/ledger.luau, z-nile/engine/main.luau (`cmd.metrics`, `ledgerRows`), z-nile/engine/costrow.luau (`readMeasured`); z-nile/.tracker/rafts/active/R0134/R0134.md and check.sh; z-nile/.tracker/issues/active/d0406/ (d0406.md, check.sh, acceptance/idea-phases.spec.luau, acceptance/watch.txt, prototype.patch, guesses.md, experiments/); `./zn capture d0406`; after `./zn sync --fetch` (origin/main 99c7caad6).

No findings.

What was checked:
- Design adherence: the engine diff is line for line the five edits of `prototype.patch` (compared hunk by hunk): `ledger.EXTRA` gains `idea` and `idea-challenge`; the phase table makes an entry for a phase it has not seen, keeps it in `unlisted`, sorts it after `EXTRA` and hides any non-lifecycle line with no minutes and no tokens; the raft table's index is guarded; `metrics <id>` appends unlisted stages in name order. No deviation, so none to record.
- Correctness: walked `cmd.metrics` with the spec's fixture and with an empty-phase measured row (`buffer` defaults an empty phase to `test`, so no blank line). Every other keyed read of a row's phase (`boardview.REVIEW_PHASES[r.phase]`, `ledger.byPhase`, `spend.luau:330`, `dispatcher.luau:553`, `main.luau:7837/7927`) is a lookup or a comparison, safe. `ledger.isPhase` has no engine caller besides the specs; `ledger.parse` and `ledger.append` still refuse an unlisted phase (AC1's `mystery` lines), as the Non-goals require. A typed `spend.md` with an unlisted phase is still skipped by `ledgerRows` with its "does not parse" message, unchanged.
- Tests: the spec asserts exact output lines and their order, has negative cases (`mystery` refused by parse and append, no `zeta` line, no `idea`/`test` line on a plain tracker), and uses no clock or randomness. check.sh's `passes` helper matches the runner's in-process failure line (`FAIL <file> :: <case>`, tests/run.luau:509); one file runs in process (run.luau:476), so a hang or crash leaves no "passed," and fails every criterion.
- Runs: `./zn check d0406` 7/7 (AC7 runs `c0043/rounds.spec` and `c0116/retired.spec`, green on this stack); `z-nile/check.sh --affected` GATE PASSED (stylua, selene, types, skills; 998 passed, 0 failed, 156 spec files); `./zn promote-check R0134` OK.
- Sequestration: `git diff --find-renames=100% --name-status` over the tracker's check.sh and acceptance paths lists only `R100` renames plus the added `acceptance/watch.txt`, which `./zn finish` writes (lesson zz-review/finish-watch-is-generated) and names exactly the two changed sources. `git diff --summary` shows no mode change.
- Architecture: `ledger.luau` stays a pure list; the reads stay at `cmd.metrics`' edge; no new module, signature or dependency edge.
- Performance: one table lookup per row in loops that already visit every row; `table.find` over at most ten phases per printed line or row. No per-frame or replication concern (tooling).
- Repository safety: the spec writes only its `trackerfix` fixtures under `.cache/d0406-idea` and `.cache/d0406-plain` (the board's `--out` is relative to the fixture, with `-O`); check.sh runs only the spec runner and `ac.sh`'s `check`. No guard file is touched.
- Bounded commands: check.sh's only commands are the spec runner; the author's reported probes are `./zn metrics` and `./zn check`.
- Scope: the capture's four Solution outcomes each have a Design step and a Checked criterion (AC2 to AC7); nothing dropped. The judgement calls in the diff (EXTRA placement, unlisted lines and stages, summary readers proven at their functions, AC7 slow line, the raft alone) each have a guess, G1 to G7, with evidence.
- Lessons: `./zn lessons metrics phase`, `unknown phase list` and `stage table sort` turned up no lesson this diff repeats. The layer adds no `harvest.md` entry to judge.

## Judged criteria (code mode only)
none (d0406 has no Judged criterion).

Verdict: approve
