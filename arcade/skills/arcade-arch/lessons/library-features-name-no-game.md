---
title: Library features name no game
when: design
tags: [arcade, leaf, config]
check: Does any file under `arcade/src/shared/Logic` spell a game's or a place's name (in a type, a list or a branch), and if the library needs the list of games or places, is it in a `src/shared` config module outside Logic (or a parameter the adapter passes), pinned by a spec that the feature's source names none of them?
---
arcade-arch rule 1 says a library feature is a leaf that knows no game. Data counts: a union of the games' names or a list of places inside a Logic feature is the feature knowing the games, even when nothing branches on it. The list belongs in a config module under `src/shared/` outside Logic (the Layout row "types, config tables"), which may require the feature, or in a catalog an adapter passes in.

**Why:** f0199 design review 001 F2: the first draft put the experience's place list in `Logic/Travel`, while f0201's prep kept its per-game catalog out of Logic, so two library features read rule 1 in opposite ways. Moving the list to `src/shared/Places.luau` left Travel a byte-for-byte copy of pickman's.

**How to apply:** grep the feature's draft for every game and place name; give the module that does name them its own place-tier case (it is where the place's adapters require it), and add a case that the feature's built source names none of them.
