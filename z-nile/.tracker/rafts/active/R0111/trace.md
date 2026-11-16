# Trace: R0111

Commit: 440a5108b0cd68b1cbf6a6f1dacc60180e281a85

## Claims

| claim | design | test | code |
|---|---|---|---|
| c0266:P1: The c0114 classified spec fails ('no feature or defect is filed in z-nile's root') now that f0263 and f0265 are filed there, which turns every z-nile gate red; either the spec or where those issues are filed has to change |  |  |  |
| c0266:AC1: the promoted `c0114/classified.spec.luau` is exactly its rewritten text (`prototype.patch`): SHA-256 of the text with ids masked and CRLF made LF. |  |  |  |
| c0266:AC2: z-ticket, the README, zz-rules, zz-test, zz-stats and the chore checklist say that every root holds chores, features and defects, z-nile's included, that a wrong spec, a hole in the watch map and a slow gate whose results are right are chores and a z-nile command, gate or guard that does the wrong thing a defect, and none still says tooling, CI or test fixes are always chores. |  |  |  |
| c0266:AC3: a run of the promoted `c0114/classified.spec.luau` runs its five cases, and its rewritten case passes and its chores-only case no longer runs. (Check-only, about 270 s: the one slow-tier run lesson zz-test/check-sh-never-runs-the-slow-tier allows when the slow spec is the file the issue changes.) |  |  |  |
| c0266:AC4: None. |  |  |  |
| c0266:AC5: None. |  |  |  |

## Source files

| file | claims |
|---|---|
