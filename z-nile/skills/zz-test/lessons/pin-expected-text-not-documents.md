---
title: Expected text is pinned, never read from a document the executor or a compaction can change
when: design
tags: [specs, sequestration, compaction]
check: Where does each expected value come from, and could the executor edit it (the issue document, a non-sequestered file) or a compaction rename it?
---
A sequestered spec that builds its expected text from the issue's own document is not sequestered: the executor can edit the block and the file together, and a compaction renames the document so the spec cannot find it.

**Why:** c0183 design review 001 F2: designs.spec rebuilt each design file from c0183.md; editing a block and its file in one commit passed, and a simulated compaction (c0183 renamed) failed with "c0183.md not found".

**How to apply:** compute the expected values in prep (keep the script in `experiments/` so a reviewer can rerun it) and pin them in the spec and in check.sh, usually as SHA-256 digests. The spec reads only the files it judges.
