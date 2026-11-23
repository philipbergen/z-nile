---
title: A line that opens or closes a gate refuses when it cannot be read
when: build
tags: [parsing, gates, fail-closed]
check: When a line in a document decides which path a ticket takes, does every form a person would write it in count, is everything else ignored, and does a line that looks like it but cannot be read refuse outright at every caller instead of falling through to another path?
from: code review and answers review of c0435, 2026-11-22 (#757)
---
A strict reader misses the line in bold, in a list or under a heading; a loose one trips on prose. Either way the caller must not continue as if no line existed.

**Why:** the Level line that raises an easy ticket was missed when written with markers, and after the first fix a line the reader could not judge made the ticket fall through to a path where it could land with no design review.

**How to apply:** strip the markers a person adds, match one exact shape, skip fenced code, table-test every spelling including real prose from the tracker, and make each caller treat 'problem' as refuse.
