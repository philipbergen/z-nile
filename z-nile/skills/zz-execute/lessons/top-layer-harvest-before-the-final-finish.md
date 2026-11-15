---
title: The top layer's harvest and lessons go in before its final finish
when: build
tags: [finish, harvest, lessons, trace]
check: Is every file this step writes after the top layer's last finish (a harvest line, a lesson file) on the list of paths a layer may gain after its finish commit, and if not, does a finish follow it?
---
After a finish commit a layer may gain only spend files, `trace.md`, `R0100.md`, review, refute and final-review files and its tickets' own documents. `harvest.md` and lesson files are not on that list, so a harvest committed after the top layer's finish leaves the layer "not finished" for `./zn trace` and `./zn done`.

**Why:** R0100 final review F2. The answers to reviews 1 and 4 were harvested after layer 5's finish and committed on the layer; the protocol (answer, harvest, commit) names no finish after the harvest. Nothing later folds them, so the top layer was unfinished by the tool's rule.

**How to apply:** for the top layer the order is fix, refute, harvest (and the final review's own harvest), lessons, `./zn finish`, restack, then `trace.md` and the final review files in commits that touch nothing else. A finish that came too early is repeated, not worked around.
