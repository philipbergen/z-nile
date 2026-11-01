---
title: Walk the table another module returns
when: both
tags: [fixtures, coverage, in-flight]
check: Does a case that checks another module's returned set (Touch.buttons, a registry, a layout) name its fields one by one, so an issue in flight that renames or reshapes them leaves nil holes the loop skips? Does it walk every field instead, fail on a shape it does not know, and require a minimum count?
---
A case that lists another module's fields by name checks less, without failing, once someone changes those fields: the missing ones come back nil and the loop skips them.

**Why:** f0147 design review 003 F3 (and d0149's prep's note): hud.spec's touch clearance read `b.snap`, `b.fire`, `b.hop`, `b.pick`; d0149 turns `Touch.Buttons` into two circles and two rectangles, so `snap` and `hop` would go nil and the circles would never be read.

**How to apply:** iterate the returned table; turn each known shape into the box the check compares (a circle into its bounding square), error on any other shape, and assert at least the number of entries the rule needs.
