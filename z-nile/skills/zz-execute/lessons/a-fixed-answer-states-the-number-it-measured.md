---
title: A fixed answer states the number it measured
when: build
tags: [review, refute]
check: For each number in a "fixed" answer (a width, a count), was the command that measures it rerun on the fixed file, and is that result the number written?
---
A refute line is a record the next reader trusts. A number in it that was meant, not measured, makes the record false even when the fix is fine.

**Why:** R0135's refute-001 F2 said a comment header was rewrapped "under 110 columns"; the final review measured the lines at 112 to 117 (final-review-001 F1, 2026-11-18). stylua does not rewrap comments, so its pass proved nothing about the width.

**How to apply:** Measure after the fix (`awk 'length > 110'` for a width) and write what the command printed.
