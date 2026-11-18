# Review 001: R0133 (code mode)
Inputs: origin/main 80029ba006c0 (fetched); layers R0133/1/c0304 7eb6b3502c1a, R0133/2/c0374 e0389d061ee9, R0133/3/c0411 d603b13239f7 (HEAD); `git diff origin/main...HEAD` and each layer's diff; R0133.md, the raft's check.sh and finished-rule.luau; c0304, c0374, c0411 documents, check.sh, acceptance/ and experiments/.

Checked by running:
- Each layer's spec change is its issue's `experiments/prototype.patch`, line for line (every `+`/`-` line of the layer's diff under `z-nile/tests` compared with the patch's).
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD` over check.sh and acceptance paths lists nothing.
- `./zn check c0304` 2/2, `./zn check c0374` 2/2, `./zn check c0411` 2/2.
- `z-nile/check.sh --affected`: GATE PASSED (the three changed specs are selected and are slow tier, so 0 run).
- `./zn promote-check R0133`: OK. RC1 (`lune run .tracker/rafts/active/R0133/finished-rule.luau` from `z-nile/`, through `./zn run`): `4 check.sh files, no path the finished rule reports`.
- No file outside the tracker changes other than the three specs. That was the Judged-by-review Non-goal of each issue, and it holds.

Read and judged:
- c0304: the `raft-tip` branch is made through the spec's `git` helper, and the push goes to the fixture's bare `origin.git` through the same helper. No real-repository path, and `c0060/retrofit` passes in AC1.
- c0374: `singleQuoted` gives the same coordinates as `rewrites.literals`. Both split at `"\n"` and count byte columns, and a word's `first` never sits on a quote byte, because the scanner's word class excludes quotes. I walked `"$(echo 'a"b')"`, `$(echo ")")`, `'"'"'`, `\'`, `x=#y`, a trailing `# it's` comment and `$((a+(b)))`. Each comes out as the shell reads it, or is reported when it does not balance. The unmodelled edges (`$'…'`, a backtick inside double quotes, a nested `( )` inside `$( )`, heredocs) are the ones the Design names.
- c0411: `projects.roots(projects.load(TOP))` reads `TOP/z-nile/projects.toml`, the same registry `./zn metrics` reads at `cwd = TOP`. The case cannot run until d0406 lands. d0406's `check.sh` AC7 (line 41) runs both `c0043/rounds.spec` and `c0116/retired.spec`, as c0411's Design requires, and d0406 carries `depends_on: [c0411]`.

Still open, and not a code finding: c0374's `## Open to the human` F1 (G4) has no ruling yet. G4 reads bare names in any single quotes as text, which is wider than the captured "a check's own helper". `./zn guesses R0133` reports all three members `not approved`, so `./zn done` waits for the person's `./zn approve`, as guess mode intends.

### F1 [low] Test time measured for c0374's layer is booked to c0304
Where: z-nile/.tracker/issues/active/c0304/spend.d/m5-max.local-5d3084bd.tsv (rows added by commit e0389d061, c0374's layer, and d603b1323, c0411's)
Evidence: c0374's layer commit appends three rows to c0304's spend file: `07:35 suite 6.599`, `07:36 1 spec 105.125` and `07:36 1 run`. c0411's commit appends one more (`07:37 1 run`). `buffer.fold` (`z-nile/engine/costrow.luau:93`, `costrow.branchOf`) books a measured line to the ticket of the branch it was recorded on. So these lines were measured while HEAD was still on `R0133/1/c0304`, after c0304's `finish` at 07:34. The 105 s single-spec run is the only run of its size in the stack. It matches c0374's step 3 (the whole `c0120/finished.spec`), but c0374's own file books no spec run at all. `./zn metrics` will under-count c0374's test cost and over-count c0304's.
Critique: rows are append-only (zz-rules, spend), so the tempting fix, moving or editing the rows, is not allowed. And a "correction" row would double-count the time.
Consequences: none for the code. The spend table for this raft stays slightly wrong.
Recommendation: leave the rows as they are. Record a `- note` entry in the raft's `harvest.md`: a layer's work, including a once-run slow spec, is run after `./zn start`/commit has put HEAD on that layer's branch, because the measure buffer books by branch. Then check whether an existing zz-execute lesson covers it before writing a new one.
Erred: zz-execute
Upstream: none

## Judged criteria (code mode only)
None of the three issues has a Judged criterion.

Verdict: approve
