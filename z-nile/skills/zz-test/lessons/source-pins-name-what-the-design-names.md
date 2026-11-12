---
title: A source pin names only what the design names
when: design
tags: [specs, adapters, sequestration]
check: Does every pattern a sequestered spec matches in source (a local's name, a private function's body, a call's exact spelling) appear in the Design as a named interface, and is a behavioural case used instead wherever one can observe the rule? And does a mutant that keeps every pinned call but ignores its result (or passes nil, or skips the code that uses it) still pass, so that a stub-engine case on what the adapter builds is needed instead? And once a behaviour case covers what a pin guarded, is the pin (an absence pin above all) deleted, since it then only forbids correct idioms?
---
Source pins are the house style for adapters, but a pin on a private name (`member.maze`, `local function finishPick`, `local function walls`) fails a correct implementation that names it otherwise, and the executor may not edit a sequestered spec to fix it.

**Why:** f0126 design review 002 F5: three adapter cases matched private names the Design never gave; the behaviour they guarded was already pinned by session cases (the player walks into the hole, ghosts stand in holes), so the pins only added ways to fail a right answer. f0158 design review 001 F2: the ring's lit/unlit case only checked that `Awareness.RING.lit.min`, `d.brightness` and `Awareness.RING.idle` were spelled somewhere, so an adapter with Roblox's transparency inverted (nearest faintest, the idle ring almost opaque) passed; f0109's fake.module could already run the real source.

**How to apply:** pin a documented name (a public function, a field of an exported type, a constant) or the absence of a wrong one (`s.maze`, the session's own field, never passed to a reader); write any name a pin needs into the Design's Interfaces; drop a pin a behavioural case already covers.

A pin that finds the right call cannot tell whether its result is used. f0126 design review 004 F1: `View.walls(m, nil, nil)`, a HudView that never laid out the bar, a bar placed off its box, boxes from a layout without the inset, and walls rebuilt every frame all passed every source pin and the whole suite. Where `tests/place/hud-shots` shows an adapter can run from its real source on a stub engine, judge it by what it builds (parts, their places and colours; how many times a call is made), with the stub require falling back to the real Logic modules.

f0126 design review 005 F2: two absence pins left beside the new behaviour cases (no `ClearAllChildren` in MazeView, no `UDim2.fromScale(0.5` in HudView) caught no mutant the behaviour cases missed and failed correct code; they were deleted.

c0164 design reviews 002 and 003: when a behaviour case replaces a text pin, try a guard mutant on each field the case holds constant, against the case, the deleted pin and every kept spec; whatever only the deleted pin killed must be killed by the case.

**Also:** c0284 design review 001 F2: a page case that removed the JSON and counted `provenanceOf(` and `<h3>Provenance</h3>` in the script passed with the cells unescaped (and would with a wrong key); the page's script can be run in node against the fake DOM that c0118's page spec uses, so assert on the pane it builds (rows, order, escaping, nothing without data).
