---
title: An adapter that must see every input says whether it counts processed input
when: design
tags: [input, adapters, stubs]
check: Does any stub in this design fire only unprocessed input at a handler that must count everything (a tracker, a last-used detector)?
---
`if processed then return end` is the reflex guard on a `UserInputService` handler, and ContextActionService marks every key and button it binds as processed (`gameProcessedEvent` true). An adapter that must see every input, such as the tracker of the controller in use, ignores the very buttons the game binds if it takes that guard.

**Why:** f0146 design review 003 F1: Pads' Design said it folds "every" input, but the stub fired only unprocessed input, so a Pads with the guard passed every check, and on a device a second player's button presses would never take over.

**How to apply:** state in the Design whether the handler counts processed input, fire at least one case's input with `gameProcessedEvent = true`, and add the guard as a mutant.
