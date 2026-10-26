---
title: A "left byte for byte unchanged" case starts from bytes the writer would never produce
when: both
tags: [specs, files, mutants]
check: Would rewriting this file with the code's own renderer change a single byte, so that the case can tell "not written" from "rewritten the same"?
---
A case that a file is left unchanged passes for a writer that rewrites it, whenever the file already holds exactly what the writer would render. A guard that skips the write then has no case that fails without it.

**Why:** c0154 design review 002 F4: the "write the duration record only when the run had the home's own files" guard survived its mutant (write whenever the run ends): the case's record had itself been written by `render`, so re-rendering it gave the same bytes.

**How to apply:** start the case from a hand-written, non-canonical text (here `1\ttests/a.spec.luau`, which the renderer would write as `1.00`), so any rewrite changes it; list the "always write" mutant as run.
