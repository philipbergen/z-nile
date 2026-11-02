---
title: Read back every scripted edit of the prototype
when: design
tags: [prototype, edits, experiments]
check: After each scripted edit of the prototype, was the changed place read back, or a spec case run that fails if the edit did not apply?
---
A scripted replace that does not match changes nothing and says nothing. A formatter that reflows the prototype between edits makes the next literal replace miss.

**Why:** c0194 prep: a replace in the prototype's command line (print the sweep's report) did not apply after the formatter reflowed that code. The sweep deleted trees silently, and no spec case noticed until a reviewer ran it (design review 001 F4).

**How to apply:** assert the pattern is present before replacing (`assert old in text`), read the lines back after, and give the behaviour a case that fails without the edit.
