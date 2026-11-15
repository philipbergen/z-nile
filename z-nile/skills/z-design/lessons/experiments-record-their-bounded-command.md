---
title: An experiment records the bounded command it ran
when: design
tags: [experiments, processes, bounded]
check: For each experiment recorded as run, does its record give the `./zn run --time <s> -- …` command (or name it a check, the gate, a `./zn` command or the spec runner), so a reader can rerun it and see it was bounded?
---
Every probe, loop or timing run that prep starts itself goes through `./zn run --time` (AGENTS.md, Processes). A record that gives only the result ("×50 took 1.63 s") can't be rerun as it ran, and doesn't show it was bounded.

**Why:** c0278 design review 001 F8: E3's timing loop was recorded without its command; it was rerun under `./zn run --time 60` in the revision.

**How to apply:** write the probe as a script, run it with `./zn run --time <s> -- bash <script>`, time inside the script, and record that command beside the result.
