---
title: The client shows what the server decided
when: design
tags: [authority, adapters, replication]
check: Does every effect the client shows for an event the server decides (a shot, a hop, a catch) take what, when and where from the server's frame, never from the client's own key press, pose or clock?
---
An effect drawn from the client's input or its render pose shows things the server never did: a beam for a fire the server ignored in a pause, a beam from where the camera was rather than the tile the server shot from, a hop the server refused. The player then trusts a picture that disagrees with the rules.

**Why:** R0035 design reviews 001 F3 (the beam was drawn on every press, even for fires the server dropped), 002 F1 (what the player sees runs 1 to 3 steps behind the server, so a client-side guess at a junction is wrong) and 003 F1 (the beam started at the client's render pose, not at the server's tile). Each was fixed by drawing the server's `Frame.shot`. The re-prep's hop follows the same rule: the camera shows `Frame.hopped`.

**How to apply:** for each effect in the design, name the frame field it is drawn from and the tick it belongs to. The client may send the request, never decide the result. Add a source or behaviour spec that fails when the adapter draws from its own input.
