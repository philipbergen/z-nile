---
title: A choice is made after the input that decides it exists
when: design
tags: [models, risk, order]
check: When a step picks something from a value on the ticket (a model from its risk), is that value set before the step runs, in the order the commands really run?
from: builder report and answers review of c0435, 2026-11-22
---
A lookup that falls back to a default when its input is missing hides the fact that the input is always missing at that point.

**Why:** the design model is chosen from the ticket's risk, but risk was set as the first act of the design step, after the model had been chosen; a missing risk reads as normal, so every easy ticket's design ran on the normal model.

**How to apply:** trace the real order of commands for one item; move the deciding value to the earliest step that can know it, as a recorded guess.
