---
title: A batched capture's commit subject lists every id
when: build
tags: [capture, land, scope]
check: Does the capture commit's subject read `tracker: new <id> <id> …` with every id written out, never a range like `c0183-c0188`?
---
`./zn capture <id>` finds an item's captured version by the newest `tracker: new` commit whose subject lists its id. A range is not a list, so the real capture is skipped and the stub's first add is reported, and scope reviews then judge against an empty Problem.

**Why:** c0183 (2026-10-31) landed six captures as `tracker: new c0183-c0188 …`; its design review found `./zn capture c0183` printing the stub commit instead.

**How to apply:** write `git commit -m "tracker: new c0183 c0184 c0185 <short title>"` for a batch, every id spelled out.
