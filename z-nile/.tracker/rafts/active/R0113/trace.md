# Trace: R0113

Commit: 5d3657ff907ad5c74985a3aa50b6f1475f01436c

## Claims

| claim | design | test | code |
|---|---|---|---|
| c0322:P1: c0084/commit-phase's case 'done records its own commit as deliver, and the raft summary shows each phase' is red on main in the slow tier since #318: the bind commit's subject gains the dispatcher's attempts note, so line 284 expects "R0010: bind f0010, f0020" and gets "R0010: bind f0010, f0020 claude unmeasured; grok unmeasured; agent unmeasured; kimi unmeasured" (found by c0248's and c0250's preps, 2026-11-13; d0303 covers the other slow reds). Either the bind subject stays the plain one and the note goes elsewhere, or the spec's expectation follows the new subject. |  |  |  |
| c0322:AC1: every row `./zn commit` and `./zn done` record for a commit has that commit's first line as its subject whatever the session reading says, the reading's tokens, AI seconds and model go on the first row only (a named model wins on every row), and the session's note is the commit's last trailer, after one `Issue:` line per row. |  |  |  |
| c0322:AC2: the CLI builds a commit's rows with one call on the commit's own message and the session's reading, builds no subject of its own, prints the note and hands it to the one trailer call, and finish's own row is as it was. |  |  |  |
| c0322:AC3: c0084's `commit-phase.spec` still expects the plain bind subject, this branch does not edit that file, and it passes, its case "done records its own commit as deliver" included. |  |  |  |
| c0322:AC4: None. |  |  |  |
| c0322:AC5: None. |  |  |  |

## Source files

| file | claims |
|---|---|
| z-nile/engine/ledger.luau |  |
| z-nile/engine/main.luau |  |
| z-nile/engine/spend.luau |  |
| z-nile/tests/inputs.tsv |  |
