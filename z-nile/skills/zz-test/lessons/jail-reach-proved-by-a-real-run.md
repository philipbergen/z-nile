---
title: What a process reaches or runs in the jail is checked per process and proved by a real jailed run
when: design
tags: [jail, process, specs]
check: For each process the design says a signal reaches (or a tool it says runs), is that process inside or outside the jail (forked before `sandbox-exec` or after), is the tool setuid (which the jail refuses to exec), and does a real jailed run, not a stand-in that shares one sandbox, show the claim?
---
The jail decides two things a design easily gets wrong by reading the process tree alone. A spec can signal only processes of its own sandbox: anything forked before `sandbox-exec` (the launcher's watchdog, the launcher, the top process) is in the specs' process group but out of reach, so a spec's `kill 0` kills the sweeper and the specs but not the watchdog, while the same group signal from outside kills them all. And the jail refuses to exec a setuid binary (`/bin/ps`: `Operation not permitted`), so a tool that works in a shell fails in a launcher a spec starts. A spec can't build the real layout either: `sandbox-exec` can't nest, so in a spec's stand-in the launcher, the watchdog and the command share the spec's one sandbox, and the stand-in shows a reading no real run gives.

**Why:** c0132's design read a spec's whole-group signal as `watchdog gone`, the outside reading. Its stand-in spec passed because there the watchdog shared the spec's sandbox; design review 001 F1 ran the prototype in a real jailed run and got `watchdog alive; 0 other` 9 times out of 9. The same prep's first prototype used `ps` to list the group, and every jailed case failed.

**How to apply:** for each process a reading names, say which side of `sandbox-exec` it was forked on, and prefer non-setuid tools (`pgrep`, `sysctl`) in anything a spec may run jailed. Prove the reading with a real jailed run: a check.sh criterion (it runs outside the jail) that runs the runner in a `.cache` fixture checkout with probe specs that send the signal from inside, and the check itself sending it from outside, as c0132's AC7 does.
