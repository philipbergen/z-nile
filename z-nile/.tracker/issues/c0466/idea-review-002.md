# Idea review 002

## Findings

- F1: Solution 1 and Solution 3 contradict each other at the fifth point. `./zn done` already writes a `deliver` row on every member (`z-nile/engine/main.luau:5671`; for example the `R0129: bind f0399 … deliver` row in `issues/done/f0399/spend.d/`). Under Solution 3 the automatic Phase 6 row is therefore always skipped, so "the item gains that stage's row" is false for `deliver`. A row written after the merge is also committed on the merged branch and pushed nowhere (`main.luau:7623`, zz-rules "record it before the merge"), so no command at that point can put it on main.
- F2: The `design-review` skip rule drops real rows. An issue's own round and its raft's coherence round both use the note `design-review-NNN` (z-design/SKILL.md:67, z-raft/SKILL.md:44), and the raft's row is shared into the members' files. A member that already holds its own `design-review-001` row would have the raft reviewer's `design-review-001` row skipped.
- F3: Problem 1's "five points" is false. z-raft/SKILL.md:44 also tells the lead to type `./zn spend <R-id> --phase design-review --begin` and again without `--begin` for the answering span. The idea lists the answer point as z-design only, so those calls stay typed. Their row has no round-file note, so Solution 3 cannot say when it is skipped.
- F4: `spend.md` is not where rows are written. The engine appends to `spend.d/<writer>.tsv`, one file per machine and checkout (`z-nile/engine/costrow.luau:126`; `buffer.luau:4` calls `spend.md` "the ledger of older typed rows"), and a delivered item such as f0399 has no `spend.md`. "The item's `spend.md` gains that stage's row" and "already holds a row of the same phase" cannot be checked as written.
- F5: Solution 4's graduation needs a ticket the idea does not depend on. `z-nile/skills/graduated.tsv` does not exist on main; c0455 creates it and its row format. c0456, c0463 and f0461 each list c0455 in `depends_on`, while c0466 lists only f0459 and f0464.
- F6: "Exactly the static steps Problem 2 lists" does not support graduating "the whole lesson". The lesson's cost is that the gate stops at any static step a builder missed, and the gate's static block also runs `./zn skills --check`, the rojo build and the Go format, vet, test and build stages (`z-nile/check.sh:302-326`). A layer that passes `./zn finish` can still fail the gate there, and `exactly` rules out the smaller route of reusing `z-nile/check.sh --static`, which `./zn land` already runs.

## Verdict

revise
