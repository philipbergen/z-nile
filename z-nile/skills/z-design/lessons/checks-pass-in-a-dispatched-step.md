---
title: A check that runs promoted specs is proven in a dispatched step's environment too
when: design
tags: [check-sh, dispatch, environment]
from: c0302 design review 001 F1
check: Do this item's checks pass under `ZN_DISPATCH=1` with `z-nile/bin` first on `PATH` (d0298's `dispatched` helper), is any spec they run known to be red there, and does that spec's fix depend on this item?
---
A raft runs interactively or under `./zn dispatch`, and a dispatched step's environment reaches the specs a check.sh starts. A spec that is red only there makes the check unpassable headless, and no edit can clear it because check.sh is sequestered.

**Why:** c0302 design review 001 F1: its check ran `c0008/done-order`, which fails one case in a dispatched step's environment on main. d0298 fixes that and depends on c0302, so on the dispatched path the two waited on each other.

**How to apply:** run the checks once in the dispatched environment during prep and record it. If a spec is red there for a reason another item owns, start that run without the step's variables and say so, with a control that shows the red.
