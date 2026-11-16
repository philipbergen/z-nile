---
title: A fetch of the branch a force-push leases against defeats the lease
when: design
tags: [git, push, lease, races]
check: For every `push --force-with-lease` the change keeps, which code refreshes the remote-tracking ref the lease reads (a fetch, a pull, a per-commit sync), and does the lease then still name the sha this checkout last saw on purpose (a recorded sha or a private ref) rather than whatever origin holds now?
---
`git push --force-with-lease=<branch>` with no explicit sha leases against `refs/remotes/origin/<branch>`. Any fetch of that branch moves the ref to origin's current tip, so the lease then permits overwriting exactly the commits it was meant to protect.

**Why:** c0254 design review 001 F5. The design fetched `origin/<branch>` before every per-commit push. A lost lead's `./zn finish` and `restack` force-push with a lease read from that ref, so they overwrote the taker's layer. A probe with two clones of one bare origin showed the taker's commit gone from origin afterwards.

**How to apply:** lease against an explicit sha (`--force-with-lease=<ref>:<sha>`) recorded when this checkout last pushed or deliberately synced, or fetch into a private ref the lease never reads. Pin it with a two-clone case in which the other clone's commit survives the force-push.

**Note** (c0254 design refute 001): a fetch into a private ref still refreshes the remote-tracking ref when the remote has a configured fetch refspec, because git updates `refs/remotes/<remote>/<branch>` opportunistically. Pass `--refmap=` (empty) as well: `git fetch --refmap= origin +refs/heads/<b>:refs/zn/seen/<b>`. The prototype's layer case found it.
