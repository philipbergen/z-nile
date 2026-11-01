---
title: Open a store inside the pcall that uses it
when: design
tags: [adapters, datastores, failure]
check: Can an adapter's `start()` throw (opening a DataStore, a service that may be missing) before the boots that come after it in Main? Is the handle opened on first use inside a pcall, so a place that cannot reach the store still boots?
---
`GetDataStore` throws where a place cannot reach DataStores (a local file, API access off), and a throw in a boot stops every boot after it.

**Why:** f0148 design review 001 F2: `Bests.start()` opened the store at boot with no pcall and ran first in both Mains, so a place without DataStore access would have had no START in the lobby and no sessions in the game place. `Boards` and `HiscoreStore` already open theirs inside pcall.

**How to apply:** open lazily inside a pcall, keep the handle once opened, treat nil as "the store is down" on every path, and add a stub in which opening throws.
