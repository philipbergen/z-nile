---
title: A fail-closed report on a file the reader cannot parse says it cannot parse it
when: design
tags: [usability, fail-closed, formats]
check: Where a reader fails closed on a file it cannot parse, does the report say that it could not parse it and the likely cause (a comment, a trailing comma), or does it only state a symptom that is false of the file (it maps nothing, it is not a project)?
from: c0273 design review 001 F5 (c0273 withdrawn 2026-11-16)
---
A fail-closed line keeps a bad file from passing, but if it names a symptom of the reader's failure ("maps no $path") instead of the failure, the author is told something false about a file that maps several paths, and looks in the wrong place.

**Why:** c0273 design review 001 F5: a `*.project.jsonc` exists to hold comments, Rojo builds it, and Lune's decoder refuses it; the home rule said `maps no $path` and graph said `is not a Rojo project`, both untrue of the file.

**How to apply:** keep the existing fail-closed line when a spec counts it, and add one line beside it (or a clause after the pinned text) that names the parse failure and its usual cause, and what is still judged. Pin the new wording in the case that feeds the unparseable file.
