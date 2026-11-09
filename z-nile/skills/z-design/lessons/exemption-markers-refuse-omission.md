---
title: An exemption marker only means something if leaving out both the marker and the record is refused
when: design
tags: [exemptions, audit, claims]
check: Does the check refuse a document that carries neither the record nor the exemption marker (after the rule's cut-over), or can the exemption be claimed by omission?
---
A rule with an exempt class is enforced only if "not exempt and no record" is an error. Otherwise the marker is decoration: omitting both gives the same result as the marker.

**Why:** c0260 design review 003 F2: an issue with neither the capture record nor the agent-filed marker was `none`, claimable and designable.

**How to apply:** make the cut-over a mark stored in the item when it is created (written only once the rule is in force on the base), refuse a marked item with neither the record nor the marker at the claim and at the later gate, and do not read history for it: an identity read from history breaks under renumbering, compaction, merge-commit landings and shallow clones (c0260 design review 004 F1).
