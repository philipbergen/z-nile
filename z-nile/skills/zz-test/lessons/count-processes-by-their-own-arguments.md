---
title: A spec that counts processes matches each one by arguments only it has
when: design
tags: [specs, counting, processes, interfaces]
check: Does every process a spec counts (a git log, a cat-file, a fetch) get matched by a flag or format that no other reader of the same command uses, and could another prepared issue that touches the same command add a process the matcher would count?
---
Counting "the `git log --first-parent` lines" of a command pins the command's total, not the feature's reads. The next writer of the same command (a heartbeat read, a stats read) adds a process of the same family, and the sequestered count goes red for correct code that the executor may not fix.

**Why:** c0284 design review 001 F4: AC3 counted every first-parent `git log` of `./zn board`; c0276's board wiring adds one (`git log --first-parent --diff-filter=A -1 origin/main -- heartbeat.luau`), so whichever layer landed second met a red spec.

**How to apply:** match on the arguments only the feature's process has (its `--format`, its pathspec, `--no-walk`), expect an exact table of counts (`toEqual({ mainline = 1, ... })`) and a zero for the shape the design forbids (one process per merge or per item); read the other writers of the command first (z-raft/interface-names-every-writer).
