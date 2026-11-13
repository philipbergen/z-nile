---
title: An emergent fix committed on another ticket's layer names its own issue
when: build
tags: [emergent, spend, layers]
check: Is this commit the fix of an emergent issue while the layer and the focus are another ticket's? Then does it carry `--issue <emergent id>`, so its lines count as that issue's rework?
---
`./zn commit` attributes a commit to the focused issue. An emergent fix that has to sit in a lower layer (that layer's gate needs it) is committed while another ticket is in focus.

**Why:** c0256, R0093 code review 001 F7: d0296's three fixture fixes were committed on c0256's layer under c0256's focus, so d0296's spend showed no lines and its rework was counted as c0256's build. Spend rows are append-only, so it could only be noted afterwards.

**How to apply:** `./zn commit --issue <emergent id>` for every commit of an emergent fix, whichever layer it lands on.
