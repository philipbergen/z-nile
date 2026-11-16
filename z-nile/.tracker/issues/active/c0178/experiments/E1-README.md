# E1: what a fixture costs, before and after (c0178 prep, 2026-11-01)

`E1-baseline.luau` builds one `trackerfix.new` fixture and reports file and process counts. It is run from a
throwaway clone under `$TMPDIR` (`cd <clone>/z-nile && lune run exp-base`), with `PATH` shims for `git`, `cp`, `pwd` and
`perl` that append "<command> <first three arguments>" to a log and run the real one. `prototype.patch` is the design's
prototype (scratch: the executor writes the code from the Design, this is the reference).

| | before (old trackerfix.new) | after (prototype, warm images) |
|---|---|---|
| files in `.cache/<name>` | 1,184 to 1,343 (varies with git's background maintenance) | 621 |
| inodes (files and folders) | 1,599 to 1,860 | 779 |
| processes (git, cp, pwd, perl, mkdir, mktemp) | 79 | 25 |
| wall time (load average 30 to 35 on 18 cores) | 4.1 to 6.6 s, sys 2.9 to 4.8 s | 1.5 to 1.8 s, sys 1.1 s |
| `git add -A` after `engine.copy` into a repository | 0.72 s, 279 loose objects | 0.07 s, 9 loose objects |
| runs that failed with "failed to copy file" | 2 of 5 | 0 of 12 cold runs after the fix (3 before it) |

## After design review 001 and the user's answers (2026-11-01)
`prototype.patch` is now the whole prototype: the library, the runner, the skills' words and the 24 promoted specs edited (setup only), 1,597 insertions and 503 deletions in 34 files (the library and skills alone are +960/-54). Based on `de3ad691`.
- Files written by the cloning specs (runner line `fixtures: N files written`): 3,107 each before; 360 to 480 (c0008, c0038, c0074, c0080, c0116, c0120), about 880 to 950 (c0001, c0044, c0046, c0050), about 1,000 for c0005 and c0045 together, 388 for `worktree-fetch`.
- Warm `trackerfix.new`: 326 files while `other` is unused (621 once read), 15 git processes, 25 in all; before 1,184 to 1,343 files and 79 processes.
- The 10 converted hand-built fixtures: no measurable time gain (their cost is the tracker commands), the files and one build path are the gain.
