---
title: A doc section says every item the Design lists
when: both
tags: [docs, review]
check: Does the section say every item the Design lists for it, or only the names the docs spec greps for?
---
A docs spec that checks names passes a section that omits the rest of what the Design asked it to explain.

**Why:** R0071 code review 001 F3: the zz-test "Bounded commands" section named the runner, hook, reaper and CPU limit but left out the engine's `ZN_ENGINE_CPU`, Monitor's allowance, the hook's blind spots and the reaper's scope; AC6 passed.

**How to apply:** compare the section with the Design's list item by item before the first review, and log any deliberate gap as a deviation.
