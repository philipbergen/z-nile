---
title: A `.cache/<name>` two spec files write out in full is one fixture directory to the isolation spec
when: both
tags: [specs, isolation, cache]
check: Does any `.cache/<name>` literal in the new specs also appear in another spec file (c0049 reads every spec's text), and is each shared name spelled apart (`"." .. "cache/<name>"`) in all but one?
---
`c0049/spec-isolation` fails the gate when two spec files contain the same `.cache/<name>`, even for a file the engine writes and the specs only read.

**Why:** c0275 prep (2026-11-12): the first gate run failed on `tracker-beater` (the fast spec and a proof) and, from the layer below, on `tracker-stamp-` and `tracker-claim-` (c0274's two specs and c0116's).

**How to apply:** grep the specs of the layers below and your own for each `.cache/` name before the gate; build the path from a constant in all but one file.
