---
title: One reader per format
when: both
tags: [parsers, drift]
check: Does a new reader of an existing format reuse the existing reader, or match it exactly and say so?
---
Two parsers of one format drift apart, and then each tool sees a different set of records. Reuse the existing reader. If it cannot be shared, copy its pattern exactly and name it in a comment and in the Design.

**Why:** R0040 design review 1 (F7): the lesson tooling's `findings` was stricter than `./zn done`'s heading pattern, so a `### F1: claim` heading would be a finding for `done` but invisible to the harvest.

**How to apply:** before writing a parser, search for an existing one of the same format, and add a spec case on input where a stricter or looser reader would differ.

**Note (c0116 design review 004 F1):** this holds for every reader of one *record* too, not only for parsers of one format. c0116's `ready` and `keepRecords` hashed a member's folder by walking the working tree, ignored files included, while the record was taken from git's blobs on `origin/main`. So Finder's `.DS_Store` made `ready` refuse a raft nothing had redesigned, and the refusal's own recovery couldn't clear it. Ask: do all the places that compute or compare this record read the same files from the same source, and can an untracked or ignored file change what one of them sees?

**Note (c0116 design review 005 F1):** "git's view" is two views: the index, and the working tree as `git add -A` would see it. Give each reader the view of what its own commit will carry. c0116's raft-review check reads tracked and untracked files, because the review may not be committed yet, while `compact`, `remap` and `renumber` hash the index, because they commit only tracked files. Before that split, an untracked work file in a member folder during a `renumber` left the record stale. Ask: can a file that this command will not commit change a hash it compares?

**Note (R0083 code review 001 F3):** a caller that pre-filters its inputs with the shared function's own patterns undoes the sharing. The board's `reviewFiles` kept only names matching the two round patterns before calling `boardview.rounds`, so a new review kind added to `boardview.rounds` alone was counted by `metrics` but not by the chart. Ask: does any caller filter or pre-select what it hands the shared rule, with a pattern the rule also owns? Hand it everything, and pin the caller's source for the pattern.
