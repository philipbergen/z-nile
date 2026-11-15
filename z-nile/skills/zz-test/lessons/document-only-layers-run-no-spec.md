---
title: A layer of documents only selects no spec
when: build
tags: [gate, docs]
check: When this layer changes only documents, which promoted specs read them, and were they run directly and recorded in the Verification log?
---
The affected gate selects nothing for a change made of `.md` files only, so the promoted specs that read the document run nowhere before the merge.

**Why:** c0264 review 001 F2: the Design said a README change selects ALL, but `watch.isSource` drops `.md`, so `--affected` reported "no specs affected" and 17 README specs ran only because the reviewer ran them.

**How to apply:** list the specs that read the changed document, run them directly through `./zn run`, and record the counts in the Verification log. Do not state "selects ALL" in a design.
