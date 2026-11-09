---
title: A test knob added to a shared fake spawns nothing when unset
when: design
tags: [fakes, knobs, shared-fixtures]
check: Does a knob added to a fake that other specs use run nothing (no process, no output) when its variable is unset, and is the line pinned exactly; if it cannot be, has every spec that uses the fake been run once with it?
---
A `sleep ${FAKE_DELAY:-0}` as the first line of every CLI fake spawns a process in every spec that uses the fake, including specs whose stall limit is 3 s and which the change was never meant to touch.

**Why:** c0279 design review 004 F2.

**How to apply:** write the knob as a shell builtin test (`[ -z "${VAR:-}" ] || sleep "$VAR"`), pin its exact text, and list the specs that use the fake.
