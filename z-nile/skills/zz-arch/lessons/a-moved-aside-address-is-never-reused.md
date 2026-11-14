---
title: When a workspace is moved aside for its successor, its old address is never handed on
when: design
tags: [state, paths, claims]
check: When a design renames, discards or replaces a worker's directory, branch or claim so that an old process can tell, can any later lookup, recreate or sweep give the old name to a new owner while the old process may still address it, and is that case pinned (the bare name after the successor was removed by hand, a lookup that falls back to the name)?
---
An old process that wakes up addresses its workspace by the name it knew. If a successor is created at that name, the old process works in the successor's tree and never learns it was replaced; a lookup that "creates the bare name when none exists" does exactly that once the successor is removed.

**Why:** c0277 design: the first draft of the plain `./zn worktree <name>` lookup created the bare `.worktree/<name>` again when the family held only discarded worktrees or none; a spec that removed the taker's copy by hand showed the old path back in use. The lookup now numbers past every discarded directory and branch (`discardedNumbers`), and `discard :: a family that has had a discard is not given its bare name again` pins it.

**How to apply:** list every path that can create the old name (the plain lookup, the takeover with nothing to discard, a sweep that frees the number) and make each count the moved-aside names as taken; add the case that removes the successor and asks again.

**Also:** c0277 design review 001 F1: a missing path is not a message. The same lookup that numbers past the old name answered a returning session's next move, `cd "$(./zn worktree R0010)"`, with the taker's copy and no word, so the old agent worked there unannounced. A lookup that returns the successor says, once, that the one it replaced was discarded, and the dispatcher stops its chain with a question instead of starting its next step there. F9: the guarantee holds while a discarded worktree of the family exists; say so, and say what ends it.
