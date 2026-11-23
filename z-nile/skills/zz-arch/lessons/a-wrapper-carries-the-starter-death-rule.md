---
title: A wrapper between a bounded runner and its starter carries the starter-death rule
when: build
tags: [processes, runner, queue, wrapper]
check: When a new wrapper (a queue, a lock holder, a logger) is put between a bounded command and the process that started it, does the wrapper itself stop its child when its starter dies and pass the stop signals on?
from: code and spec reviews of #744 to #748 and d0434, 2026-11-21 (filed in #749)
---
The bounded runner stops its command when the starter ends. A wrapper in between becomes the starter the runner sees, so unless the wrapper watches its own parent, the command outlives the session.

**Why:** d0426 gate queue (2026-11-21, code review): the queue wrapper held the lock and ran the gate; the code review found that when the session that asked for the gate dies, the wrapper and the gate keep running and keep the queue.

**How to apply:** a wrapper exits, and stops its child, when its parent pid changes or a stop signal arrives. Test by killing the starter and asserting the child is gone and the lock free.
