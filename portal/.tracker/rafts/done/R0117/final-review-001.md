# Review 001: R0117 (final mode)
Inputs: the finished stack at 469e4ac62 on `R0117/3/f0206` (layers f0205 5c1f2b370, f0208 360f1756c, f0206 fad773df7, then 9c793c8e1 and the trace skeleton 469e4ac62), base 2ac4694ba; `git diff 2ac4694ba...HEAD`; R0117.md, review-001.md, refute-001.md, harvest.md; f0205.md, f0208.md, f0206.md, their check.sh, acceptance/ and results.txt; `./zn capture` of each; the landed arcade library (`Wallet`, `Boards`, `Receipts`, `Places`, `Prices`, `TestPurchase`); `z-nile/engine/trace.luau`.

Runs on 469e4ac62:
- `./zn check f0205` 7/7, `./zn check f0208` 7/7, `./zn check f0206` 8/8.
- `./zn check R0117`: 6/6 (RC0: the affected gate, the three members' checks and promote-check; RC1: the composed map).
- `./zn trace R0117 --check` on the filled table: it fails, and only because origin/main has moved past the stack's base (F1). In a scratch clone under the session's scratchpad, with origin/main and main pinned to the base 2ac4694ba and the filled `trace.md` copied in, the same command printed `ok: R0117` and exited 0. Every row and cell passes, and so does every `## Source files` row.

The trace was filled from the three documents, the specs' recorded cases and the sources at fad773df7. Each design cell cites the claim's own line and the Design paragraphs that answer it. Each Checked criterion's test cell cites its `check.sh` line and the single-line cases that prove it. Multi-line case names are covered by the check.sh line, because the check reads one `::` name per cell. Each code cell cites the functions that do the work. The "None." rows and the lead-in rows cite the way R0110 and R0121 did: the section line, the `finish` line and a nominal source line. The Observed rows cite headless proxy cases and say that the step was not run. The joints carry their proofs: f0206 place :: "the client's Main starts CarouselView before every adapter that fills its slots: PlayButtons and BoardsView" is the boot-order guard (design review 001 F1, ruled (c)), and f0206's budget flood cases cover P5 and AC5.

On substance: I read every changed source against its Design section. `Cards`, `CarouselView`, `Plays`, `Invites`, `PlayButtons`, `BoardRelay` and `BoardsView` do what §4 and §5 (f0205), §5 to §7 (f0208) and §2 and §3 (f0206) say. The five shared lines are exactly the Whole-raft design's composition. The deps block is `# Carousel and Card are leaves; so are Pairing and Arena` then `Play -> Card`. I found no code without a claim and no claim without code.

Three things are already open to the human and are not repeated here:
- code review 001 F1: the slow-store pass. It is cited in the design cells of f0208:P4 and AC3. The case they cite (server.spec "a check still busy after CHECK_SECONDS …") passes only on a stubbed `Wallet.pass`.
- code review 001 F2.
- the owed layer-3 Beta observation (f0206:AC12).

### F1 [high] `./zn trace R0117 --check` fails on the finished stack: origin/main moved after the skeleton, so layer 1 is no longer stacked on main
Where: `portal/.tracker/rafts/active/R0117/trace.md` (the `Commit:` row); `z-nile/engine/main.luau:5089-5108` (each layer must descend from `layergit.mainTip()`, which is origin/main).
Evidence: run in the worktree, the check's only finding besides its consequences is `row Commit, commit: table is stale (R0117/1/f0205 is not stacked on the layer below)`. Once the staleness is set, `finishedIssues` stays empty, so every `check.sh` test cell also reports "did not run green for this stack": 33 rows, all of them consequences of the same thing. The base is 2ac4694ba. origin/main is now 48f0e43e3, eight commits later:
- tracker commits: R0126 done, R0127 readied, R0129, and the designed-by backfill;
- c0397, which changes `arcade/tests/acceptance/f0201/{config,receipts}.spec.luau`;
- under `portal/`, only `R0122.md`, `R0123.md` and `R0124.md`;
- none of them touches `arcade/src` or this raft's files.

With origin/main pinned to 2ac4694ba in a scratch clone, the filled table passes (`ok: R0117`, exit 0). So the cells are sound, and what is owed is a restack.
Critique: a final reviewer may not restack or commit. The tempting fix is to treat this as noise and land as is. `done` runs the same check, though, and the table names a finish commit that will not exist after a restack.
Consequences:
- `./zn restack` rewrites all three layer commits. The `Commit:` line then names a commit that is not in the stack, and the check reports the table stale.
- The table must be regenerated with `./zn trace R0117` on the restacked stack, and these filled cells copied onto it. Every cited line stays valid when the restack brings no change to `portal/src`, the three issue documents (above their Verification logs), the specs or `results.txt`. On today's origin/main it brings none.
- If R0127 (f0395, readied on main, which changes `arcade/src/shared/Prices.luau` and `TestPurchase.luau`) lands before the restack, the restack brings sources that f0205's `card.spec`, f0208's `play.spec` and its `client.spec` read. Then every member's check and the raft check must run again before the table is regenerated. That is the gap of code review 001 F2, and the full gate at the merge covers it.
Recommendation:
1. Restack onto the then-current origin/main.
2. Rerun `./zn check f0205`, `f0208`, `f0206` and `./zn check R0117`.
3. Re-finish the top layer as zz-execute does, regenerate the skeleton, copy this table's cells onto it unchanged (each claim's text is unchanged), and run `./zn trace R0117 --check` until it prints `ok`.
4. Commit `trace.md` and this review after the new finish commit, touching only tracker files.
5. In the same pass, apply F2's fix.

### F2 [low] The records name commits that are not in the stack
Where: f0205.md Verification log, last line ("restacked … onto origin/main 719f7bedd; layer commit 7f31ceb09"); f0208.md Verification log, last line ("layer commit 1390586c5"); f0206.md Verification log, last line ("restacked onto origin/main 719f7bedd"); R0117.md `## Addressed during execution` ("Restacked onto origin/main 719f7bedd").
Evidence: the stack's layers are 5c1f2b370, 360f1756c and fad773df7 on 2ac4694ba. `git merge-base --is-ancestor 7f31ceb09 HEAD` is false. `git diff --stat 7f31ceb09 5c1f2b370` lists only the c0402 files that main withdrew at 2ac4694ba. So a later, tracker-only restack replaced the commits that the log lines name, and the lines were not updated.
Critique: a reader who follows a log's commit, for the human's rulings or a later unfold, finds a commit outside the branch. The harm is small, because the content is the same.
Consequences: F1's restack will move the commits again, so a correction made now would go stale too.
Recommendation: after F1's restack, append one Verification log line to each issue and edit the R0117.md bullet. Each names the final base and that layer's finish commit, written after the re-finish so that it names the commits the trace pins.

Verdict: changes
