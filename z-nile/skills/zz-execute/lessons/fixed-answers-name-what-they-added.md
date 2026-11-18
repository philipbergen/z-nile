---
title: A fixed answer names what the fix added, not only its sha
when: build
tags: [refute, finish, squash, review]
check: Does every `fixed <sha>` answer in the raft's refute files also name the file, case or line the fix added, so it still resolves after `./zn finish` squashes the fix commit into the layer's one commit?
---
A code review round is answered before the layer is finished again, so a `fixed <sha>` answer cites a commit that the re-finish squashes into the layer's one commit. Once the branch is deleted and git collects garbage, that sha leads nowhere, and the record of how the finding was closed is only the prose beside it.

**Why:** R0120 final review 001 F1: refute-001 answered F1 "fixed f993e796c", which `./zn finish f0186` squashed into 0a4d16abb; no branch contains it. Done rafts R0103, R0109 and R0115 carry the same unreachable shas.

**How to apply:** keep the `- F<n>: fixed <sha>: <what changed>; consequences: …` form `./zn done` reads, and make `<what changed>` name the path (and the case, when it is a spec) the fix added or edited, so a reader can find it in the finished commit. A fix made after the last finish (a final refute) can cite that finish commit or a later tracker commit, which stay reachable.
