---
title: Read back every scripted edit of the prototype
when: design
tags: [prototype, edits, experiments]
check: After each scripted edit of the prototype (or of a mutant), was the changed place read back, or a spec case run that fails if the edit did not apply, and does the edit refuse a pattern that occurs more than once?
---
A scripted replace that does not match changes nothing and says nothing. A formatter that reflows the prototype between edits makes the next literal replace miss.

**Why:** c0194 prep: a replace in the prototype's command line (print the sweep's report) did not apply after the formatter reflowed that code. The sweep deleted trees silently, and no spec case noticed until a reviewer ran it (design review 001 F4).

**How to apply:** assert the pattern is present before replacing (`assert old in text`), read the lines back after, and give the behaviour a case that fails without the edit.

**Also:** c0279 design review 003 F1: a first-match replace for a mutant hit `runner.luau` line 141 (the start-time check) instead of the run loop's marker branch at line 237; the mutant survived, and the survival was written up as a hidden engine path until the next review read the fixture's copy. Make the mutation helper assert the pattern occurs exactly once, print the changed hunk, and read the fixture's copy of the file before explaining a survivor.
