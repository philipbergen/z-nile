---
title: An automatic side effect keyed to "this checkout did X once" needs an end and a subject check
when: design
tags: [automation, claims, heartbeat]
check: What removes the record that triggers this automatic effect (a throttle file, a remembered claim), does the effect re-check that its subject (the stamp, the owner) is still the one recorded, and can the main checkout ever hold one?
---
A throttle or memory file that outlives its subject keeps acting for ever: it beats a finished or taken-over claim, or keeps a dead dispatcher's claim alive from the one checkout the user keeps working in.

**Why:** c0265 design review 002 F1: a per-checkout autobeat entry, never removed, made the main checkout beat every claim it had ever beaten and beat a taker's new stamp.

**How to apply:** key the effect on a fact that says this checkout works this subject, drop the record when the subject's identity on origin differs, and say which checkouts never hold one.
