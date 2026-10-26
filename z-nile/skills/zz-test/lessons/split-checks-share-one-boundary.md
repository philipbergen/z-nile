---
title: A check that splits a file into a part that may change and a part that must not defines the first positively and compares every other byte
when: both
tags: [specs, boundaries, pins]
check: Is the part that may change defined by a strict positive pattern, and does the check compare every other byte of the file (line 1 and an unterminated last line included)? Does a mutant at each edge (the first line, the boundary, a comment-prefixed code line, the last line) turn it red?
---
Two readers that each find "their" part of a file leave the text between them unchecked; and one reader with a loose notion of the changeable part ("a line starting `--` is a comment", "line 1 is neither", a line splitter that drops a last line with no newline) leaves text in neither too.

**Why:** c0134 design review 001 F1: header.spec cut accept.spec's header at the first non-comment line, while check.sh AC2 compared the body from the first `local` line, so a code line between them passed. Review 002 F1: with one reader, line 1, a `--[[ ]] code` line and an unterminated last line still passed.

**How to apply:** define the changeable part by one strict pattern (here: a contiguous run of lines that are exactly `--` or start with `-- `, right after line 1), keep every byte when splitting (`string.split`, not a `([^\n]*)\n` match), compare everything else byte for byte, and add a mutant at each edge: the first line, the boundary, a comment-prefixed code line, the last line.
