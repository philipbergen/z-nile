---
title: A gate that stops standing in front of a check hands on every refusal it made
when: design
tags: [refusals, readiness, walk]
check: When the design moves a rule out of the path (it no longer refuses, it only classifies), which refusals did that rule make that nothing behind it makes, and does each now have a check, a case and its words, so the walk never answers an action the command then refuses?
---
A rule that used to refuse for every input (f0420's light rule in front of `./zn ready <issue>`) often caught things the checks behind it never look at. When the rule becomes a classifier (light or not), those refusals vanish silently, and the walk starts offering an action the publish guard then refuses.

**Why:** f0464 design review 001 F3: `light.reason` refused a ticket whose document has no `raft:` line; readycheck has no such rule, so after f0464 the walk would answer `ready <id>`, and the publish guard would refuse the move with general words, the same answer again on every ask.

**How to apply:** list each refusal the old gate makes, and name the check that makes it after the change (or say it is meant to pass now). Add the missing ones before the readiness judgement, with a case each.
