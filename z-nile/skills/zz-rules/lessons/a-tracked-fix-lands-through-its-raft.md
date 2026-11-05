---
title: A fix for a tracked issue lands through its raft, however small or urgent
when: build
tags: [raft, landing, lifecycle, chore]
check: Does a PR I am about to merge change code, specs or skills for a tracker issue (one I just captured included)? If so, is it the raft's PR, and will `./zn done` close the issue, or is it a plain PR that leaves the issue open in the backlog?
---
`./zn done` and the raft rules gate only a raft's PR. A plain PR (the kind captures and preps use) merges on a green gate without them, so a fix merged that way leaves its issue designed by no one, in no raft, never `done`, with no spend, and nothing in the tracker notices.

**Why:** c0237 (pickman's lobby-tooling spec pattern broke the type stage on `main`): the user said "Go ahead just fix main", and the fix was captured as a chore but merged as a plain PR (#230). The issue stayed `new` in the backlog until the user asked how it had merged, and it then had to be designed, rafted, readied and run after the fact.

**How to apply:** an urgent fix is still `z-ticket`, then `z-design` (a small design and one review round), `z-raft`, `z-ready`, `z-run`, `./zn done`. "Just fix it" authorises hurry, not skipping the lifecycle; if the speed matters more, say so and ask the user to waive it, and record the waiver. A plain PR is for captures, preps and rafting only.
