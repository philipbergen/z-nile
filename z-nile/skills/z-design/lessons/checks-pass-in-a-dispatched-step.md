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

**Note** (c0286 prep, 2026-11-15): stripping only the step's `ZN_DISPATCH*` and `ZN_PUBLISH_*` variables is not enough for a spec that starts a nested `./zn dispatch` in a fixture (`c0117/dispatch-cli`, `control-cli`, `tests/tooling/dispatch-guards`). With `z-nile/bin` still first on `PATH` and `ZN_REAL_GIT` set, the fixture's dispatch took the wrapper `z-nile/bin/git` as its real git, the wrapper called itself without end, and the run exhausted the machine's processes twice (about 8,800 of 10,666). Strip `ZN_REAL_GIT`, `ZN_REAL_GH` and every `z-nile/bin` entry of `PATH` too, check `command -v git` first, and watch `ps -ax | wc -l` while the suite runs.
