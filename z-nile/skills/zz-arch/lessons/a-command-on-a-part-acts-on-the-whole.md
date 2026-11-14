---
title: A command on part of a claimed whole refuses or acts on the whole
when: design
tags: [rafts, claims, commands]
check: When a command can be pointed at one member of a claimed whole (an issue of a readied raft), does it refuse and name the whole, or act on the whole, rather than move the member alone?
---
Moving one member of a readied raft leaves the raft claimed and active while its member sits elsewhere, a state no other command expects.

**Why:** c0250 design review 001 F2: `./zn block c0210` on a member of a readied raft moved that issue alone to the backlog, and a later resolve sent it to `new` with its `raft:` still set.

**How to apply:** resolve a member to its whole from tracker state on `origin/main` and refuse with the command that acts on the whole.
