# Review 001: R0135 (final mode)
Inputs: HEAD 8a796399b (top layer c0388 finished at 17170f937) against origin/main ce2c39c9d (`./zn sync --fetch`: synced, nothing new), `git diff origin/main...HEAD`; R0135.md, its check.sh, review-001.md, refute-001.md, harvest.md; c0388.md, check.sh, guesses.md, acceptance/roots.spec.luau, acceptance/watch.txt; `./zn capture c0388` (capture f09eb82b4, no marker).

Checks run by the reviewer: `./zn check c0388` 3/3 on this head (AC1 runs `c0042/cli.spec.luau` on the real tracker). `./zn trace R0135 --check` prints `ok: R0135` on the filled table; it reports no stale `Commit:` line (the two commits after 17170f937 change only the raft's and the ticket's tracker folders).

Trace: every row of `trace.md` is filled. The tool refuses the promoted `c0042/cli.spec.luau` as a test citation (not a spec of ticket c0388), so the P1 and AC1 rows cite `check.sh:15`, the `check "AC1:` line that runs it, and name the case in words. AC4 and AC5 are the "None." lines under Judged and Observed, not criteria; their cells say so and are marked vacuous.

Substance, claim by claim:
- P1 (capture): the hand list is gone from `cli.spec.luau` (no `.tracker/` literal, no `fs.readDir`); `ondisk.items` reads `projects.roots(projects.load(top, true))`, which is the same registered set `board.sources` reads (`projects.load(dir).projects`, board.luau:632), in backlog, `active/` and `done/`, for rafts and for issues, with the id patterns of `store.isRaftId` and `store.isIssueId` written out again, not shared with the page. The case passes on main's tracker with arcade's and portal's rafts where they are. The document's Problem and Solution only add detail to the capture (the difference grew from 1 to 8, the closed issue behind it); no captured outcome is dropped or moved to Non-goals.
- AC1: proved by the run above, not by construction: the helper walks folders itself and the page comes from `board.collect`.
- AC2: each of the six cases of `roots.spec.luau` fails for its own rule (a root not in the registry, a retired root, `rafts/retired/`, malformed ids, a closed issue, a missing folder, a missing registry, the text of the cli spec's two halves). The fixture is plain folders under the home's `.cache/c0388-roots`: no git, no write elsewhere.
- AC3: `tests/inputs.tsv:29` and the three new lines of `c0042/watch.txt` are present and are what `check.sh:19` greps.
- Non-goals (the Judged section leaves them to the reviewer): the diff changes `z-nile/tests/acceptance/c0042/` (cli spec, helper, watch), `z-nile/tests/inputs.tsv`, one lesson file under `z-nile/skills/z-raft/lessons/` (harvested from review-001 F1) and tracker files. No engine file, no `projects.toml`, no item folder moved, and the cli spec's two other cases are byte for byte main's.
- Sequestration: the check.sh and acceptance globs list only `A .../c0388/acceptance/watch.txt`, the watch `./zn finish` writes; its two lines are the stack's two source files.
- Guesses G1 to G3 are each pinned by a case and none shrinks the captured outcome; G4 and G5 are rafting choices with no code.
- Nothing extra: both source files are accounted for in the trace's Source files table.

### F1 [low] refute-001 says the helper's header was rewrapped under 110 columns, and seven of its comment lines are still wider
Where: z-nile/.tracker/rafts/active/R0135/refute-001.md, F2; z-nile/tests/acceptance/c0042/ondisk.luau:2-7 and :27
Evidence: `awk 'length>110'` on `ondisk.luau` at 17170f937 prints lines 2, 3, 4, 5, 6, 7 and 27 with lengths 117, 116, 115, 115, 114, 112 and 115, against `column_width = 110` in `z-nile/stylua.toml`. The refute answers review-001 F2 with "the header is rewrapped under 110 columns". The 153-character line the finding quoted is gone, and the misplaced comment did move to `ondisk.items`, so the part of F2 that could mislead a reader is fixed; the width claim is not true as written.
Critique: the record says a thing was done that was not. It costs nothing at run time (stylua does not rewrap comments, the gate is green, and `cli.spec.luau` beside it carries comment lines of 112 to 118 from earlier overrides), which is why it is low. The tempting fix is to rewrap the seven lines now.
Consequences: rewrapping changes a source file after the top layer's finish, so the layer must be re-finished and the trace's `Commit:` line and the cited `ondisk.luau` line numbers redone (lesson zz-execute/final-lessons-ride-a-refinish), for comment widths no check reads. Correcting the record changes no source file.
Recommendation: answer in `final-refute-001.md` that the header was wrapped to under 120, not 110, and leave the file as it is; or, if the author prefers the comments at 110, rewrap lines 2-9 and 27-28, rerun `./zn check c0388`, re-finish the layer and repoint the trace. Either closes it; neither changes behaviour.
Erred: zz-execute
Upstream: none

Verdict: approve
