---
title: Open a store inside the pcall that uses it
when: design
tags: [adapters, datastores, failure]
check: Can an adapter's `start()` throw (opening a DataStore, a service that may be missing) before the boots that come after it in Main? Is the handle opened on first use inside a pcall, so a place that cannot reach the store still boots? And does every store call that stands before a player-visible step (a teleport, a session), each one of them when there are several in a row, have a time limit in that place too, shorter than any other bound (Travel's cap) that could run out first, and does the design say what a late answer means? In test mode, does a place that cannot open its store still play its test flows (a stand-in), and does a boot that waits do so in its own thread?
---
`GetDataStore` throws where a place cannot reach DataStores (a local file, API access off), and a throw in a boot stops every boot after it.

**Why:** f0148 design review 001 F2: `Bests.start()` opened the store at boot with no pcall and ran first in both Mains, so a place without DataStore access would have had no START in the lobby and no sessions in the game place. `Boards` and `HiscoreStore` already open theirs inside pcall.

**How to apply:** open lazily inside a pcall, keep the handle once opened, treat nil as "the store is down" on every path, and add a stub in which opening throws.

**Also:** f0148 design review 002 F2: the lobby's choice write had no limit, so a silent store held the teleport until Travel's 60 s cap let a second press go; it now waits at most 5 s.

**Also:** f0201 design review 001 F4: the arrival bounded its claim but not the pass read that followed it, so a slow MemoryStore held an arrived player with no run; every call before the step is bounded, a second call after the first included, and what a late answer means is stated (a pass read not back in time counts as a pass, and its late answer still removes the entry). F5: where the store cannot be opened, test mode still has to work (G1 puts Studio in test mode), so a test store gets a per-server stand-in with the same contract; a live store never does. F13: a client boot that waits for a server object (`WaitForChild`) stops every boot after it; wait in a thread of its own.
