---
title: A PR's state and newest comments are read before every push to it and every report that it was updated
when: both
tags: [github, landing, reporting, coordination]
check: Did I read `gh pr view <n> --json state,comments` (the state, and the newest comments) right before this push to the PR's branch, or this report that the PR was updated, and does my report quote the state I read?
---
Another session or the user can close or merge a PR while an agent works on its branch, usually with a comment that says where the work went. A push to that branch still succeeds, but nobody reads it, so the work is lost and every "PR updated" report is false.

**Why:** c0271: PR #256 (a prep of c0264) was closed by another session with a comment naming the prep that replaced it, and an agent kept pushing review rounds into it for hours while its reports said the PR was updated.

**How to apply:** read `gh pr view <n> --json state,comments` before you take a PR as where the work lives, and again before every push to its branch (`git push`, or a `./zn` command that pushes) and every report about it. Only an `OPEN` PR takes the push. A `CLOSED` or `MERGED` one takes nothing: report its state and newest comment, and stop. A report that a PR was updated quotes the state it read (zz-rules skill, Landing a change, step 2).
