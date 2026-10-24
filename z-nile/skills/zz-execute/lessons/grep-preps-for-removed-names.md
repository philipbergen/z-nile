---
title: A removed name is searched in other items' sequestered specs
when: build
tags: [regression, sequestration, coordination]
check: For each name this raft removes or renames (a remote, an attribute, a key, an API), does `grep -rn <name> tracker/ --include='*.spec.luau'` find an item outside this raft that still pins it, and is there an issue telling its prep?
---
The gate runs `tests/`, so it only guards promoted specs. Sequestered acceptance specs of rafts still in prep or readied (`tracker/**/acceptance/`) are not run by it, and they pin the tree as it was when they were written. A raft that removes a name breaks them silently: the other raft goes red only when its executor runs its checks, and nobody may edit those specs except that raft's prep.

**Why:** R0034 review 001 F3. f0065 replaced the `PlayAgain` remote with `ToLobby` and `LobbyStatus`; R0035, in prep at the same time, had a sequestered `f0100/acceptance/place.spec.luau` that pins the remotes as `{Intent, PlayAgain, Ready, Snapshot}`. Only the reviewer found it; c0130 now tells R0035's prep.

**How to apply:** before the code review, grep `tracker/` (excluding your own raft's items) for every name your diff removes or renames. For each hit, file an issue naming the spec, the line and the new value, and name it in the PR description; never edit another item's sequestered spec.
