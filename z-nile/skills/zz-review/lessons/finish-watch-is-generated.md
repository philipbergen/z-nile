---
title: Finish watch files are not sequestered edits
when: build
tags: [review, sequestration, watch]
check: Is the only acceptance addition the watch.txt that ./zn finish generated from this layer's sources, with no spec or check.sh change?
---
The sequestration diff permits `acceptance/watch.txt` as an addition: `./zn finish` is its only writer, and it records the layer's source files for affected selection. It is not an executor-written acceptance fixture. Any changed or added `.spec.luau` or `check.sh` remains a high finding.

**Why:** R0072 review-001 met the generated file on an otherwise unchanged sequestered tree; rejecting it would make every finished layer fail review.

**How to apply:** verify the file's paths against the layer diff and the zz-test capture rule, then explicitly distinguish it from sequestered specs in the review. Code mode item 2 still says any other change is high. c0326 captures the edit that names this generated file as the one allowed addition, in that item and in zz-test's sequestered bullet.
