---
title: A fix that removes a forced workaround reopens the steps the workaround covered
when: design
tags: [defect, workaround, protocol, order]
check: Once the fix lands and nobody takes the workaround, which steps of the protocol run for the first time in their written order, and has each been run on the prototype with the commands the skill names?
---
A defect that forces every agent through a workaround (finish again, a plain commit) hides the protocol steps around it: the workaround happens to satisfy them. Remove the cause and those steps run as written for the first time, with whatever order mistakes and gaps they always had.

**Why:** d0333 design review 001 F3, F4 and F5. Accepting the raft's `spend.md` after a finish meant zz-execute Phase 5 step 1's `./zn commit` stayed on the finished layer, so step 3's "verify the check, then commit the table" reported that commit as added before `trace.md`; a lower layer's review commit now read as finished to `start` while the trace still refused it; and the harvest commit of step 4 (d0344) still unfinished the layer with no way through written down. The forced second finish had covered all three.

**How to apply:** in the design, list the steps of the skill between the defect and the landing, run them in order on the prototype with the prescribed commands (not the workaround), and fix the wording of any step that only worked because of the workaround. Name each state the fix makes newly reachable, with its message and its way back.
