---
title: One reader per format
when: both
tags: [parsers, drift]
check: Does a new reader of an existing format reuse the existing reader, or match it exactly and say so?
---
Two parsers of one format drift apart, and then each tool sees a different set of records. Reuse the existing reader. If it cannot be shared, copy its pattern exactly and name it in a comment and in the Design.

**Why:** R0040 design review 1 (F7): the lesson tooling's `findings` was stricter than `tracker.sh done`'s heading pattern, so a `### F1: claim` heading would be a finding for `done` but invisible to the harvest.

**How to apply:** before writing a parser, search for an existing one of the same format, and add a spec case on input where a stricter or looser reader would differ.
