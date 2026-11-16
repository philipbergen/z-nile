---
title: A screen's ContextActionService binding sits strictly above the default controls, with its lower bound stated
when: design
tags: [input, adapters, priority]
check: For each ContextActionService binding a design adds, which other bindings take the same keys (Roblox's PlayerModule binds movement, jump and camera at `Enum.ContextActionPriority.Default`, 2000; a library screen above it), is its priority strictly between them (never equal: at equal priority the action bound last wins, and the control module binds again when the input type changes), is each bound pinned by its own case, and what happens to the screen's keys while a TextBox is focused (the chat) and under the platform's touch controls?
---
A binding at the default priority ties Roblox's own controls. At equal priority ContextActionService asks the action bound most recently, and the PlayerModule binds its actions again whenever the player switches input type, so a screen bound once at start can lose a shared key (ButtonA, the gamepad's jump) to the default controls after a controller is picked up, and nothing in a headless spec shows it.

**Why:** f0205 design review 001 F4: the portal's carousel bound its keys at 2000, the PlayerModule's own priority, and its spec pinned only the upper bound (below the test purchase screen's 3000). Typing in the chat and the platform thumbstick over the cards were not examined either.

**How to apply:** pick a priority strictly above 2000 and strictly below any screen that must win over it, pin both bounds (mutants: the lower one and the upper one), pass the keys on while `UserInputService:GetFocusedTextBox()` is set, turn `GuiService.TouchControlsEnabled` off in a place with no character, and put what only a device shows (a controller connected late, the chat focused, a swipe over the thumbstick's half) in Observed with a fallback.
