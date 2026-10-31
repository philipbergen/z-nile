---
title: Set the focus to the issue a commit changes before recording its spend
when: build
tags: [spend, focus, commit]
from: R0061 code review 001 (the reviewer's candidate lesson)
check: Does each commit's spend row sit in the spend.md of the issue whose files the commit changes, with `./zn focus <issue>` run (or `--issue <issue>` passed) before the commit?
---
`./zn commit` records a commit's minutes on the issue in focus. A fix to one member made while another member holds the focus goes on the wrong issue, and `./zn metrics` then overstates one issue's cost and understates the other's; the raft's total hides it.

**Why:** R0061: a fix to c0135's spec (5e0dbd30) and the code review's own spend were both recorded on c0137, which still held the focus from the commit before.

**How to apply:** before each `./zn commit`, run `./zn focus <issue>` for the issue whose files the commit changes, or pass `--issue <issue>`. A raft-wide row (a review) goes on the issue the reviewed change is in, or is shared as the tracker's proportional attribution does.
