---
title: A spec that resets its fixture before every case cannot see what one command leaves for the next
when: both
tags: [fixture, publish, state]
check: Does any case run the publishing command right after a command that does not publish wrote the same file, with no reset between them?
---
When a command publishes a file that other commands also write locally, at least one case runs it on the state an earlier command left, with no reset in between. A reset before every case proves each command alone and nothing about the two together.

**Why:** c0348 design review 001 F1: every case of its `deliver-publish.spec` began with `git reset --hard origin/main`, so no case saw that the deliver publish sent the worktree's whole `spend.d` file, capture, prep and design-review rows of the branch included. Both criteria that state the rule passed on the leak.

**How to apply:** for each file two commands write, order one pair of cases so the second runs on what the first left, and assert on what reached `origin/main` (the other command's rows are absent) as well as on what the command printed.
