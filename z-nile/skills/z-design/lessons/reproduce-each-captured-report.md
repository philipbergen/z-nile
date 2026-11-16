---
title: Reproduce each captured report
when: design
tags: [experiments, scope]
check: For each failure the capture reports, has prep tried to reproduce it under the reporter's conditions (their environment, the machine's load and shared resources, the branch they were on), with each attempt and its result recorded, and is a report that never reproduces put to the user, not kept as a passing check that cannot fail or dropped by the author?
---
A defect that lists several failures is often a mix of causes. A failure that passes every time prep runs it is not fixed by the issue. A check that only says it passes cannot fail for the reported reason, and dropping it narrows the capture.

**Why:** d0298 design review 001 F2. The capture named `c0049/parallel-runner (1)` among main's reds. Prep ran it solo, five times, and once inside a dispatched step, and it passed every time. The draft kept it in AC4 as "a regression case", with no reproduction and no root cause. The reviewer named a mechanism no run had tried (the machine-wide worker lanes, while other suites hold them). Round 1 held seven and then all eight lanes, and it still passed.

**How to apply:** For each reported failure, write down the reporter's conditions and try each of them: the environment (a dispatched step, a clean one), contention for shared resources (lanes, locks, CPU under a whole-suite run) and the branch name. Record the commands and results. If none reproduces it, say so in the Reproduction and put to the user whether the issue may be done with that report unexplained, as long as its acceptance still requires the spec to pass.
