---
title: Pin every argument a call site passes
when: both
tags: [wiring, seams]
check: Is every argument the call site passes pinned by a spec whose fixture makes a wrong value visible, not masked by a default or a fallback?
---
Testing a pure function does not test the call that feeds it. Each argument the adapter passes (a filter, a source map, a path) needs a spec through the real entry point, with a fixture where a wrong or empty value changes the output.

**Why:** R0039 needed rounds 3 and 4 because the rebind candidates `jail()` passed were unpinned. R0040 design review 1 (F2) found the same gap: `renderPrompt` could pass empty sources and the prompt spec still passed, because every fixture lesson had a `from:` that hid the missing count.

R0012 code review 001 (F3): every fold spec exercised the pure `Touch.track`, but nothing pinned Controls' `snap = rect` argument or how it dispatched the effects. `snap = nil`, `onLook(dy, dx)` and `FireServer(effect.kind)` all passed the gate.

**How to apply:** for each call from the adapter into the pure module, list its arguments in the Rules table, each with a mutant that passes a wrong value and a fixture in which that value shows.
