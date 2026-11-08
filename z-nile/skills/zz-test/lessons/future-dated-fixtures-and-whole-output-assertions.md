---
title: A "max over all" or "count of all" assertion proves nothing after earlier cases wrote fake-future values
when: both
tags: [fixtures, time, assertions]
check: Does every time-based assertion filter to the case's own item and to values its own run could have produced (not the fake-future epochs earlier cases wrote), and does an environment-dependent half (a refusal) set its variable explicitly?
---
Earlier cases that date state with a fake clock leave values ahead of the real clock, so a later "newest is at least now" or "exactly one ref" assertion is satisfied or broken by state the case did not make.

**Why:** c0265 design review 002 F2 and F3: a count over every beat included another item's, and a `newest` was met by beats written 1,300 fake seconds ahead, so a loop that never beat passed.

**How to apply:** filter by the item's own key and by `<= real now`; set environment variables a refusal depends on explicitly (an empty value), because a child inherits the runner's.
