---
title: A new part in the maze is checked against every path the eye takes
when: design
tags: [camera, rendering, hop, edge-cases]
check: For every part the design adds to the world (a marker, a beam, a pillar), can the camera's eye reach it on an ordinary move (walking its corridor, a hop or a long hop over it, a held wait), and what does the player see as the eye nears it and passes through it: is that stated in the Design, decided, and pinned by a case?
---
A part placed on the rail's tiles sits on the line the camera walks. A hop lifts the eye into the height band of anything tall, and while airborne the player passes over pellets without eating them. So a part tied to a pellet that is still there can stand in the eye's path at the very moment it is shown. Flying through a near face fills the screen for a few frames, then the part vanishes once the eye is inside (a part's faces are not drawn from within).

**Why:** f0235 design review 001 F4. The power pellets' beacons (3 studs wide, from 3 to 20 studs) were shown while airborne. A hop down a power pellet's corridor took the eye through the lit pillar at about 30 studs/s: a 70%-opaque neon band across the middle of the screen. No edge case, AC or OC named it.

**How to apply:** for each new part, list the eye's paths that reach it (walk, hop, long hop, a held wait at a spot), and state what the player sees there. Then either hide the part near the eye (a clearance in the part's data table, a pose getter, and a case that walks the pose through it) or record the pass-through as a **(prep)** choice with an Observed step.
