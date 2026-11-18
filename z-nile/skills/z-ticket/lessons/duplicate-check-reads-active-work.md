---
title: The duplicate check reads active and prepared work
when: design
tags: [capture, process]
check: Before `./zn new`, did you search every unfinished item (`./zn list active` and the prepared ones, not only `./zn list backlog`) for the same failing spec or command, with `grep -rl <spec path>` over the roots' issue documents outside `done/`, and read each hit's Problem for a ticket that already captures it or could be expanded to?
---
z-ticket step 5 says to look for overlaps with `./zn list backlog`. An item a raft is already building is in `active/`, and a title search of the backlog cannot see it: the same Problem is then captured, challenged and designed a second time, and the two fixes can contradict each other.

**Why:** c0407 (2026-11-17) was captured for the red case of `c0084/commit-phase.spec.luau` after a search of `./zn list backlog` for a few title words. Active c0322 (raft R0113, built and approved, waiting at `finish`) had the same Problem and fixed it the other way (the subject stays plain, the note becomes a trailer). c0407's design review (F1, high) found it; the capture, the idea challenge and a full design were wasted, and either landing order would have turned the other item red.

**How to apply:** Search by what is broken, not by title: `grep -rl "<spec or command>" --include='[cdf]0*.md' */.tracker/issues | grep -v /done/`, and read each hit's Problem. `./zn list active` shows what is being built. An overlap with active work means: carry that raft on (`./zn work next <R>`), and capture nothing. An overlap with an unfinished ticket that is not being built means: propose expanding that ticket (its scope is the user's to change) instead of filing a second one. File a new ticket only after the search found neither.

**Note (user, 2026-11-18):** "we cannot keep filing all these dupes spend some more time before filing to see if there is a fitting ticket to expand or that captures it already." c0407 was closed as a duplicate of c0322 that day. The search is part of the capture, not a formality before it: read the Problem of every hit, in `backlog/`, `active/` and the prepared items, before `./zn new`.
