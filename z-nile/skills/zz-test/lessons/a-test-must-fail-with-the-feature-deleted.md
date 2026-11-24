---
title: A test must fail with the feature deleted
when: both
tags: [tests, fixtures, vacuous]
check: For each new rule, is there a case whose expected answer differs from what the code gives with the rule removed, checked by removing it?
from: test reviews of f0421-can and f0420-pick, 2026-11-22 (#754, #758)
---
A fixture where the filtered answer equals the unfiltered one, or where a second rule gives the same result, proves nothing about the rule under test.

**Why:** 11 of 19 mutants survived in each of two test reviews on one day: theme tests that passed with the theme filter deleted because the expected unit was also the lowest id; a 'stays a fact' case where another rule kept the unit out anyway; a 'next blocker' case that used a worker lacking nothing. The full gate had passed on both.

**How to apply:** build fixtures where the rule changes the answer; delete or invert the rule and see the case go red before committing; a passing gate is not evidence that the tests bite.
