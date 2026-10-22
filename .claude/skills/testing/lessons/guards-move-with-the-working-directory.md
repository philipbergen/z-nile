---
title: When a check's working directory moves, every guard tied to a folder moves with it
when: both
tags: [guards, fixtures, sandbox]
check: When this changes the folder a check.sh or a spec runs in, does every guard tied to a folder (git's ceiling and the .cache sentinel, the lock, the jail, the link sweep, the tripwire's lists, the reviewed .cache writers) cover the new folder too, including when the check runs inside another run's jail, and does the folder the guards used to cover keep its fence?
---
A guard stated as "git never looks above `<checkout>/.cache`" protects only the folder it was set up for. Move the commands to another folder and the testing skill's `.cache/<unique name>` convention moves their fixtures there too, outside every guard. A fixture whose `git init` failed then lets git find the real repository. Nothing goes red, because the guard still holds where it used to.

**Why:** c0120 design review 001 F1. c0120 runs pickman's `check.sh` files from `pickman/`, but `ac.sh` still fenced only the root, so `pickman/.cache/<name>` was outside git's ceiling, and the scratch reproduction found the real repository there. The fix fences the home as well. The sweep that followed found a second gap of the same kind: the tripwire listed worktrees under the run's own `.cache` only.

**How to apply:** list every guard tied to a folder, and for each say which folder it now covers. Set up the guard for the new folder too, reading only environment where a write would be refused (inside a jail). Add a spec case that runs git in a folder with no repository under the new `.cache`, and in that `.cache` itself, and expects no repository.

**The folder left behind keeps its fence.** c0120 design review 005 F2: once spec runs moved into project homes, the root's `.cache` (every run's own before) was in no run's ceiling and the gate made it without a sentinel, so on Linux git in `<top>/.cache/fx` found the real index. Specs written for the old folder (unconverted preps, copied promoted files) still write there. When a run moves into a subfolder, the folder it used to fence keeps its fence: list the guarded folders before the move and after, and prove each one with a case (here, the runner fences the top's `.cache` before the jail, and a probe from a home finds no repository there).

**Every home, not a hand-listed set.** c0120 code review 004 F3: after fencing the run's home and the root, a run from `pickman/` still left `z-nile/.cache` open (unjailed, git there found the real repository; a symlinked one was written through). Derive the folders from the registry, so a new home is covered when it is listed, and refuse a bad `.cache` before the first write there (the gate's builds wrote `<home>/.cache` before any refusal).
