---
title: Name every coordinate space, and the engine call that measures it
when: design
tags: [adapters, layout, input, engine]
check: For each point, size and rectangle that crosses an adapter (an input position, a layout box, a hit-test rectangle), is its space named (screen, core-UI safe area, device safe area, GUI inset), with the documented engine call that measures it, does every spec that compares two boxes shift each from its own frame into one before comparing, and is every conversion between two spaces a pure function with a case on a documented non-zero sample?
---
Roblox has several overlapping frames: the full screen, the core-UI safe area, the device safe area, and the legacy GUI inset. Each engine value (`InputObject.Position`, `ViewportSize`, `AbsolutePosition`, `GetInsetArea`, a ScreenGui's `ScreenInsets`) lives in one of them. A design that says "pixels" without naming the frame mixes two of them, and on a desktop or an un-notched sample every inset is zero, so the specs cannot tell.

**Why:** R0012 design reviews. 001 F3: `ScreenInsets.None` with `GetGuiInset` put the HUD under the notch. 002 F1: the radar was laid out in DangerHud's device-safe frame but checked in HudView's core-safe one. 003 F1: touch positions arrived in the GUI-inset space while the snap rectangle was in screen pixels. 004 F1: `ViewportSize` is the device safe area, not the screen, so the layout was 118 px too narrow on a notched phone. f0158 design review 001 F1: the danger ring's clearance spec laid the HUD out with zero insets and put the ring and the HUD in one frame, so on a landscape phone under the 58 px top bar the ring's top dots sat on the score and level blocks while the spec stayed green.

**How to apply:** add a coordinate-spaces table to the design (the space, its origin, the engine call that measures it, and who uses it). Make each conversion a pure Logic function, and test it on the engine's documented non-zero sample, not on zero insets.
