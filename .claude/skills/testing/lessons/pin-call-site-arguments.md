---
title: Pin every argument a call site passes
when: both
tags: [wiring, seams]
check: Is every argument the call site passes pinned by a spec whose fixture makes a wrong value visible, not masked by a default or a fallback?
---
Testing a pure function does not test the call that feeds it. Each argument the adapter passes (a filter, a source map, a path) needs a spec through the real entry point, with a fixture where a wrong or empty value changes the output.

**Why:** R0039 needed rounds 3 and 4 because the rebind candidates `jail()` passed were unpinned. R0040 design review 1 (F2) found the same gap: `renderPrompt` could pass empty sources and the prompt spec still passed, because every fixture lesson had a `from:` that hid the missing count.

R0012 code review 001 (F3): every fold spec exercised the pure `Touch.track`, but nothing pinned Controls' `snap = rect` argument or how it dispatched the effects. `snap = nil`, `onLook(dy, dx)` and `FireServer(effect.kind)` all passed the gate. Code review 002 (F1) then found the source pins added for that covered a helper's body but not its call: deleting `hold()` from the input handler passed every spec. The pins became a behavioural spec that runs the adapter's real source on a stub engine.

**How to apply:** prefer driving the adapter's real source on a stub engine to pinning its text; a text pin on a helper proves nothing unless the call on the hot path is pinned too. For each call from the adapter into the pure module, list its arguments in the Rules table, each with a mutant that passes a wrong value and a fixture in which that value shows.

R0035 code review 001 (F1, F2): the same gap came back on new adapter branches. Controls' key handler gained Fire, Jump and the held arrows (Begin, End and Cancel), and HudView gained `Hud.shotIcons(l, lives, shots)`. The stub engine only kept the touch signals, so the handler bound by `BindActionAtPriority` was thrown away: a never-released arrow, `LookUp` sent to the server, or lives passed as 0 all passed the gate. When an adapter gains a branch, extend its stub-engine spec to run that branch; a new source pin is not enough.
