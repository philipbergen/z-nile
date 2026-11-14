---
title: A spec that asserts an order by time sets every fixture commit's date
when: both
tags: [time, fixtures, ordering]
check: Does an "oldest first" assertion compare a fixed date with a commit made at run time?
---
A fixture commit made at run time carries the wall clock; stored rows with fixed dates then sort before or after it depending on the day the spec runs, and a correct implementation fails.

**Why:** c0263 design review 003 F4: who.spec's stored rows were dated 09:00 and 09:30 while the fixture commits were dated when the spec ran, so `approved` sorted before `idea`.

**How to apply:** pass `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` for every fixture commit, pick the stored rows' dates between them, and assert the exact event list.
