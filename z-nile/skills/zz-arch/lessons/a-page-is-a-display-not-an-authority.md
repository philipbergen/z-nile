---
title: A page that shows agent-written facts is a display, not what the person approves
when: both
tags: [app, approval, facts, binding]
check: When a page shows text and offers an action on it, is the action bound to a fingerprint of the thing itself and checked at the moment of acting by a process the writer of the text does not control, and does the page say that it is only a display?
from: code review of f0437 step 4a, 2026-11-22 (#755)
---
The page reads a file any agent can write, and the tracker can change after the page loaded. An action that names only an id acts on whatever is there when it runs.

**Why:** the Approvals view copied a bare approve command for the ticket shown. A design pushed after the page loaded, or a forged facts file, would have been approved unseen; the terminal flow already refused a changed contract and showed a summary first, and the button skipped both.

**How to apply:** the copied or sent action carries the run and the contract hash, the recorder recomputes and refuses on a difference, the confirmation text comes from the tracker at that moment, and the view states that what is approved is what the recorder shows.
