---
title: Before keeping a text unchanged to avoid a conflict, read where the other edit lands
when: design
tags: [merge, conflicts, restated-rules]
check: When this design keeps a text as it is because changing it "would conflict with" an in-flight item, has the other item's diff or design been read for the exact lines it changes, and does it change this line or the line next to it?
---
Git conflicts only where two edits change the same lines or lines next to each other. A design that avoids a needed edit because another issue "rewrites that paragraph" may be avoiding a conflict that does not exist, and pays for it with a stale rule; one that inserts a line next to a line another issue edits gets a conflict it did not plan for.

**Why:** c0291 design review 001 F1 and F7: the design left a sentence in 25 skills unchanged because c0136 and c0181 "both rewrite that paragraph", but c0136 inserts its paragraph before the role bullets and leaves them unchanged, so the edit met nothing; meanwhile the new zz-rules bullet sat on the line after one that c0136, c0112 and c0181 all rewrite, which a probe showed does conflict.

**How to apply:** for each in-flight item named as a reason, open its prototype patch or its Design and note the lines it edits; an insertion on the line after an edited line counts as touching it (probe it with `git merge-tree` in a scratch repo when unsure). Name every real overlap in Existing work with its resolution (keep both, then re-run both docs specs).
