# Answers to design review 001 (R0069)

The review read the record `[c0112@7f9cf9cf1ce7, c0247@115948858213]`. All three findings are accepted. F1 is a member design change, so c0112 is unfolded (`./zn unfold R0069 c0112`) and goes back to z-design. That leaves R0069 with one member, c0247, and the record `[c0247@115948858213]`. F2 and F3 are fixed in the rewritten R0069.md. No member's design was edited.

### F1 [high] c0112's ledger copy, run outside `keepRecords`, makes `ready` refuse every backlog raft whose members' ledgers it rewrites: c0112 unfolded
The fix the review gives changes c0112's design and its sequestered `check.sh` ac6: route each ledger write through `keepRecords`, and narrow ac6 to `Grouped:` tokens in coherence reviews. z-raft never edits a member's design (§4), so c0112 is out of the raft. Its redesign is z-design's to do. The other paths (keep the raft and refold every affected raft after it lands; change `isDesignFile`) are left to that redesign and to the user. Until c0112 is claimed for design, it is a prepared issue with no raft, and the next `./zn raft-plan` would fold it again. The rafting report names it for z-design.

### F2 [low] the cross-raft order names rafts that don't hold the items: fixed
The waits are restated per item from `./zn find` at rafting time and moved to `## Cross-raft waits`: c0256 has no raft member, and c0260 has no raft. The "written in R0092" sentence and the stop for R0092's lead are gone.

### F3 [low] where code-review harvests live, and when c0112's specs are promoted: moot
Both statements were about c0112 and c0247 meeting inside one raft. With c0112 out, that text is gone. The rule they got wrong still holds for this raft's executor: a raft's code reviews are harvested in `R0069/harvest.md` (`./zn lessons --uncovered R0069`), as zz-execute says.
