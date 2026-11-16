---
title: A PR's state and newest comments are read before every push to it and every report that it was updated
when: both
tags: [github, landing, reporting, coordination]
from: c0271 capture note (PR #256) (ticket withdrawn 2026-11-16)
check: Did I read the PR's state, head and newest comments (`gh pr view <n> --json state,headRefOid,comments`) right before this push to its branch, or this report that it was updated, and does my report quote the state I read?
---
Another session or the user can close or merge a PR while an agent works on its branch, usually with a comment that says where the work went. A push to that branch still succeeds, but nobody reads it, so the work is lost and every "PR updated" report is false.

**Why:** c0271: PR #256 (a prep of c0264) was closed by another session with a comment naming the prep that replaced it, and an agent kept pushing review rounds into it for hours while its reports said the PR was updated.

**How to apply:** read `gh pr view <number or branch> --json state,headRefOid,comments --jq '{state, headRefOid, newest: [.comments[-2:][] | {author: .author.login, createdAt, body}]}'` before you take a PR as where the work lives and again before every push to its branch and every report that it was updated. Only an `OPEN` PR takes the push. A `CLOSED` or `MERGED` one whose head is in your history or in origin's branch takes nothing: report its state and newest comment, and stop. One whose head is in neither was an earlier use of the name (z-stop's start fresh). A read that fails twice stops the push; a PR you merged yourself keeps its post-merge report. A report that a PR was updated quotes the state it read.

**Note (c0271, 2026-11-16):** a closed or merged PR is this work's when its head is in the history you push or in origin's tip of the branch (`git fetch origin refs/pull/<n>/head`, then `git merge-base --is-ancestor <headRefOid> HEAD` exits 0, or the same against `FETCH_HEAD` of `git fetch origin <branch>`); when both tests exit 1, or origin has no such branch, it was an earlier use of the name (z-stop's start fresh) and the branch gets a new PR. `gh` exits 1 both for `no pull requests found` and for a network or auth failure: any answer but that one is no answer, so retry once, then push nothing and stop. Also read the PR in zz-execute Phase 4 before each review round's push, so "carry on" never passes a failed or closing read. (The matching bullet in zz-rules' Landing a change and the Phase 4 sentence that c0271's design drafted were not written when its ticket became this lesson.)
