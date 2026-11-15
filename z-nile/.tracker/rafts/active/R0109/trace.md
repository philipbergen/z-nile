# Trace: R0109

Commit: 8fadb10d98115d9ec0961ea78b25d97f95d2a898

## Claims

| claim | design | test | code |
|---|---|---|---|
| d0333:P1: c0306's prototype (2026-11-14) reported that ./zn commit after ./zn finish rewrites the raft folder's spend.md, which layergit.isPostFinishPath does not list: it allows only the raft folder's review-, refute-, final-review- and final-refute- files, trace.md, the raft document and spend.d/. So the finished layer reads as not finished. Yet zz-execute Phase 5 says to commit trace.md and the final review files with ./zn commit --phase code-review. The prototype's done fixture had to run ./zn finish again after that commit. It has not been reproduced on main. What should happen: reproduce it with a raft that finishes its last layer and then commits its final review with ./zn commit; then either the post-finish rule takes the raft's spend.md, or commit no longer rewrites it after finish. |  |  |  |
| d0333:AC1: `layergit.isPostFinishPath` takes the raft's own `spend.md` and no other new path. |  |  |  |
| d0333:AC2: `trace.staleReason` keeps the table current when commits after the finish and after the table also rewrite the raft's `spend.md`, and still calls any other file stale. |  |  |  |
| d0333:AC3: a finished raft that commits its trace table, final review and final refute with `./zn commit` stays finished (`./zn trace`, and `./zn work next` does not ask for another finish) and passes `./zn trace --check`, each commit with its spend row. |  |  |  |
| d0333:AC4: `./zn done` lands that stack with the finish commit made before those commits, and their spend rows are in the landed ledger. |  |  |  |
| d0333:AC5: with the table and the final review committed, a `./zn commit` of any other file still unfinishes the layer and makes the table stale, and `./zn done` refuses because the layer is not finished. |  |  |  |
| d0333:AC6: the trace's fast spec stays green. |  |  |  |
| d0333:AC7: zz-execute Phase 5 commits the table and the final review files with `./zn commit` and then verifies the check, and Phase 2B says a lower layer with any commit after its finish is finished again. |  |  |  |
| d0333:AC8: None. |  |  |  |
| d0333:AC9: None. |  |  |  |

## Source files

| file | claims |
|---|---|
| z-nile/engine/dispatch.luau |  |
| z-nile/engine/layergit.luau |  |
| z-nile/engine/trace.luau |  |
| z-nile/engine/work.luau |  |
