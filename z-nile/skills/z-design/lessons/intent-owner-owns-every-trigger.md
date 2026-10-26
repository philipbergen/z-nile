---
title: The issue that adds an intent owns every trigger for it
when: design
tags: [dependencies, input, ownership]
check: For each trigger of a new intent (a key, a button, a stick gesture, a touch control), does the issue that adds the trigger land after the intent exists, and is that issue the one that defines the intent?
---
When the user adds a trigger for a new intent while another issue's prep is running ("stick up boosts too" during the gamepad's prep), decide its owner from `depends_on` before either stream builds it. A trigger placed in the issue that lands first can't reach the later issue's intent without a dependency cycle: the intent's module and the server's acceptance of it don't exist yet.

**Why:** f0143 design review 002 F1: the left stick's double push up was relayed to f0146's stream, but f0146 lands before f0143 (`depends_on`), `Logic/Boost` exists only from f0143, and the server refuses `"Boost"` until then. The same hand-off had already failed once for L3 (design review 001 F2).

**How to apply:** the issue that defines the intent owns every trigger for it, on every device. The earlier issue leaves the hook (the module the trigger lives in) and points at the owner in one line; the owner puts the module in its Touched list and gives each trigger a running case.
