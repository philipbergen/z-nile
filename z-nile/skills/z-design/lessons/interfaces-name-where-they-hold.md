---
title: An engine value other issues rely on names the environments it holds in
when: design
tags: [interfaces, roblox, testing, environments]
check: For each engine value or API behaviour this design hands to later issues as an interface (a server kind, an id, a retry), has the platform guide's own limitations section been read and quoted, and does the interface say where it holds (production, Studio Test, Team Test) and which Observed steps must therefore run where it holds?
---
A value that is right in production can read differently in the test environments the next issues will use first, and an interface that does not say so sends them down the wrong branch in their own playtests.

**Why:** f0208 design review 001 F6: the portal told the game places that a reserved server reads `PrivateServerId ~= ""` and `PrivateServerOwnerId == 0`, but Roblox's teleport guide, Known limitations, says "In Test mode, both are always empty, even for private servers" and "In Team Test, every server is private"; the same section advises retrying reserved-server teleports, which the design had not considered.

**How to apply:** read the guide's limitations section for every API an interface leans on, quote it in the Unknowns, state in the Interfaces where the value holds, move the steps that need it to the environment where it holds (Beta here), and decide each piece of advice the section gives (a retry) with a case.
