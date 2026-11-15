---
title: A PR's state and newest comments are read before every push to it and every report that it was updated
when: both
tags: [github, landing, reporting, coordination]
check: Did I read the PR's state, head and newest comments (`gh pr view <n> --json state,headRefOid,comments`, trimmed as zz-rules' Landing a change step 2 says) right before this push to its branch, or this report that it was updated, and does my report quote the state I read?
---
Another session or the user can close or merge a PR while an agent works on its branch, usually with a comment that says where the work went. A push to that branch still succeeds, but nobody reads it, so the work is lost and every "PR updated" report is false.

**Why:** c0271: PR #256 (a prep of c0264) was closed by another session with a comment naming the prep that replaced it, and an agent kept pushing review rounds into it for hours while its reports said the PR was updated.

**How to apply:** follow zz-rules skill, Landing a change, step 2, before you take a PR as where the work lives and again before every push to its branch and every report that it was updated. Only an `OPEN` PR takes the push. A `CLOSED` or `MERGED` one whose head is in your history or in origin's branch takes nothing: report its state and newest comment, and stop. One whose head is in neither was an earlier use of the name (z-stop's start fresh). A read that fails twice stops the push; a PR you merged yourself keeps its post-merge report. A report that a PR was updated quotes the state it read.
