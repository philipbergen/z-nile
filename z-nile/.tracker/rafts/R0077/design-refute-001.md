# Answers to design review 001 (R0077)

The review read the record `[c0123@d08f1e683355, c0160@6dac0a9fe81c]`. All four findings are accepted. F2 is answered by taking c0123 out of R0077 (`./zn unfold R0077 c0123`), which also settles F3's interface and F4 inside this raft. c0123 becomes a raft of its own. R0077 is back to its own record, `[c0160@6dac0a9fe81c]`: one member, no coherence review needed. No member's design changes.

### F1 [high] the Order names non-members and repeats members: fixed
`## Order & dependencies` now names only c0160, once. The cross-raft facts, with their item ids, moved to a new `## Cross-raft waits` section. `raftSection` stops at the next `\n## `, so `stack.order` no longer reads them. The probe re-run on the new section finds no non-member and no repeat. The same defect is in nearly every raft on main, R0072 included, and in five active ones. R0072, R0094, R0095, R0096 and the two new rafts of this rafting are fixed the same way. The engine side is captured as its own issue, and the lesson is z-raft/order-names-members-once.

### F2 [medium] the members share no wait, and grouping puts c0160 behind R0078, R0070 and c0189's raft: fixed by unfold
c0123 is unfolded. c0160 waits only for R0062 again. c0123 (1,200 lines) is its own raft, and it waits for c0194 (R0070) and c0189 (its own raft).

### F3 [medium] the Theme misquotes the decisions, and c0160's spec under c0123's cleaner is unproven: fixed by unfold, the interface recorded
The misquoted Theme was the fold's text and is gone: R0077's Theme is its own again. The interface remains between the two rafts, whichever lands second. It is now written under Cross-raft waits: c0160's spec starts `lune`, `git` and `pwd` by name and must pass under c0123's `cleanenv.list` `PATH`. The second to land runs the other's specs in its full gate, so a red case there stops that raft's executor. That executor never edits the other's sequestered spec. No experiment was run at rafting time.

### F4 [low] `c0055/setup-run.spec.luau` is a file both c0189 and c0123 edit: carried to c0123's raft
Neither member is in R0077 now. The adjacency (c0189's `zn` stub and `zn hooks` order against c0123's `cleanenv` copy in `build()`) is written in c0123's new raft, which waits for c0189's.
