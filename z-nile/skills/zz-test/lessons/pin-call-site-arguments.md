---
title: Pin every argument a call site passes
when: both
tags: [wiring, seams]
check: Is every argument the call site passes pinned by a spec whose fixture makes a wrong value visible, not masked by a default or a fallback (and, when a rule depends on which of several sources a value is read from, does the fixture give those sources different values, even where the fake makes them equal)?
---
Testing a pure function does not test the call that feeds it. Each argument the adapter passes (a filter, a source map, a path) needs a spec through the real entry point, with a fixture where a wrong or empty value changes the output.

**Why:** R0039 needed rounds 3 and 4 because the rebind candidates `jail()` passed were unpinned. R0040 design review 1 (F2) found the same gap: `renderPrompt` could pass empty sources and the prompt spec still passed, because every fixture lesson had a `from:` that hid the missing count. f0158 design review 002 F1: the fake engine gives every ScreenGui the screen's size, so an adapter that sized the danger ring from the radar's screen (`gui.AbsoluteSize`) instead of its own core-UI screen passed every spec, and on real phones under a top bar that ring sits on the lives block.

R0012 code review 001 (F3): every fold spec exercised the pure `Touch.track`, but nothing pinned Controls' `snap = rect` argument or how it dispatched the effects. `snap = nil`, `onLook(dy, dx)` and `FireServer(effect.kind)` all passed the gate. Code review 002 (F1) then found the source pins added for that covered a helper's body but not its call: deleting `hold()` from the input handler passed every spec. The pins became a behavioural spec that runs the adapter's real source on a stub engine.

**How to apply:** prefer driving the adapter's real source on a stub engine to pinning its text; a text pin on a helper proves nothing unless the call on the hot path is pinned too. For each call from the adapter into the pure module, list its arguments in the Rules table, each with a mutant that passes a wrong value and a fixture in which that value shows.

R0035 code review 001 (F1, F2): the same gap came back on new adapter branches. Controls' key handler gained Fire, Jump and the held arrows (Begin, End and Cancel), and HudView gained `Hud.shotIcons(l, lives, shots)`. The stub engine only kept the touch signals, so the handler bound by `BindActionAtPriority` was thrown away: a never-released arrow, `LookUp` sent to the server, or lives passed as 0 all passed the gate. When an adapter gains a branch, extend its stub-engine spec to run that branch; a new source pin is not enough.

R0035 code review 002 (F1): the stub-engine spec for HudView's bars compared positions relative to their parent frame, so deleting the frame's own placement passed. Compare GUI positions in the screen coordinates the player sees: the parent's placement plus the child's.

c0154 code review 001 (F1): the pure `render(old, runs, keep)` was pinned, but nothing pinned what the runner passes it: `keep` on every run (not only a full one), or `{}` instead of the recorded record, each turned every `--affected` run into a record of only its subset, and schedule.spec stayed green. A partial run through the real runner, from a hand-written record, pins both.

f0146 design review 001 (F1): source pins on Controls and Sticks passed `if action == Pad.CONTINUE` (an action compared with a key name, never true) and `Pad.steer(steer, x, -y)` (an inverted stick). Running both on a stub engine with a recording handler per bound code list, a scripted `GetGamepadState` and a Heartbeat the case fires killed both.

c0170 design review 001 F1: a spy on a pure rule's input compared one spec's requires only; a call site that handed over a filtered list (only `@tests/lib/` requires) passed. A spy case compares every element the call site gathers with an independent reading.

c0170 design review 002 F2: a spy compared what the call site gathered with the real tree, which had no example of one kind of input (a fixture dep in a helper or unit spec), so a call site that dropped that kind passed. A spy is only as strong as the kinds today's tree holds; hand the pure function the whole source (the graph) and let it choose, or seed a synthetic input with every kind.

c0180 design review 002 F2: a new flag (`--recorded`) that narrows selection had cases on the selector alone, so the gate could drop it and every criterion still passed. A flag a caller must pass gets a case through every real caller (here a rule over `z-nile/check.sh`'s selection lines).
