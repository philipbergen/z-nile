---
title: A refusal keyed on the dispatcher must say how the dispatched pipeline still gets the thing done
when: design
tags: [dispatch, confirmation, headless]
check: For every refusal keyed on `ZN_DISPATCH=1`, which dispatched step needs that command, and what lets that step through (a stop for the user, a person's step in a terminal, or a different command)? When a dispatched step asks the user (`questions.md`), does every choice it offers name something that step or the user can do, and does the retried step read the answer (`$ZN_DISPATCH_DIR/answered-<n>.md`) before it asks again?
---
A command that refuses a dispatched run is right when an agent must not do it, and wrong when a later dispatched step has to do it and has no other way. The pipeline then ends in a dead step that no spec runs, because the specs exercise the refusal and the step in isolation.

**Why:** c0260 design review 009 F1: `./zn idea --confirm` was refused under `ZN_DISPATCH=1`, and z-design's own dispatched confirmation of an unattended capture called it.

**How to apply:** name, in the Design and the skill, the way through: the step stops with `questions.md` and a person runs the command in a terminal (as for `./zn approve`), or a different command does the dispatched form. Add a spec case that follows the dispatched step to its end.

**Note (c0270 design review 001 F3):** a headless "join it or stop" question offered "join", which no dispatched step can do (the dispatcher runs z-design in its own `prep-<slug>`), and the retried step, prompted the same, never read `answered-<n>.md` and would ask again. The question names the three choices that work, and the step reads earlier rulings first.
