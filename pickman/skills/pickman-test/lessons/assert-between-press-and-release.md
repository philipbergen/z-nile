---
title: An input case asserts between the press and the release
when: both
tags: [specs, input, controls]
check: Does each key, button or tap case assert after the press and again after the release, so that an action sent on the wrong phase fails?
---
A case that sends the press and the release and then counts the intents can't tell an action sent on the press from one sent on the release, and players feel that difference.

**Why:** f0126 design review 007 F1: "F and Y going down each send the pick once" passed with the pick sent on the key going up.

**How to apply:** after the press, assert the intent is there; after the release, assert nothing was added; add the wrong-phase mutant to the Rules table.
