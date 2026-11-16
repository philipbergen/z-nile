# c0155 design refute 003

- F1: fixed: each field is nudged by +1 and by -1 (351 runs, about a second). consequences: a Rules row and mutant M14 (`fire` compared with `<=`), run and killed.
- F2: escalated to the user, who decided "Own action, like keys (Recommended)" (recorded in the Problem as a Scope decision, 2026-10-31): a new spec case requires every pad button beyond today's seven to have an action of its own, on the real `Pad.BUTTONS` and on planted maps. consequences: AC1's label and text, a Test plan line, a Rules row and mutant M15 (`ButtonB = "Jump"` added to `Logic/Pad`), run and killed; f0126's and f0143's planned buttons pass it (planted in the case).
- F3: fixed: the Design and the spec header say the spec reaches the cases through `Touch.buttons` and `Pad.BUTTONS`, and that a rewrite of f0146's case through `Pad.action` would need a chore. consequences: none.
- F4: fixed: the d0149 bullet now says what turns red and how d0149's Override check finds it (affected selector and the path grep), not a promise d0149's documents do not hold; the handoff tells d0149's prep. consequences: none.
