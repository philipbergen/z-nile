---
title: Gate runs leak macOS kernel memory until a reboot, so run few and one at a time
when: both
tags: [gate, machine, kernel, panic, parallel]
check: Before starting a gate or a batch of spec runs, has the kernel zone meter been read (`zprint | awk '$1=="data.kalloc.1024"{print $7}'`), is no other gate running on the machine, and is this run needed (something changed since the last one)?
---
Each `z-nile/check.sh --affected` run leaves about 3,400 to 4,900 more in-use elements in the macOS kernel zone `data.kalloc.1024`, and only a reboot frees them. The count adds up across every session, worker and subagent on the machine. When the zone map is exhausted the machine panics and everything running is lost.

**Why:** on 2026-11-21 the owner's Mac panicked with "zone map exhausted ... likely due to memory leak in zone [data.kalloc.1024] (19G, 20764352 elements allocated)" during a session that ran many gates in parallel subagents, after 17 days of uptime. Measured after the reboot: 840 elements idle, then 5,500, 10,400 and 13,800 after three affected gates, with no decay at rest. Fixture-heavy spec files add hundreds each; a pure spec adds none. The leaking operation is not yet named (d0426): plain spawns, `sandbox-exec`, git init, clone and worktree add, file churn, `lune` starts, ptys, `flock` and the live daemon each added nothing in batches of 100 to 300.

**How to apply:** while iterating, run the spec files you changed by name, and the gate once at the end. Run one gate at a time on the machine, counting your subagents' runs; a reviewer runs spec files, not the gate. Never rerun a gate when nothing changed. The gate reads the meter before it starts (`z-nile/lib/kzone.sh`): it warns at 5,000,000 elements and refuses at 10,000,000 (`ZN_KZONE_WARN`, `ZN_KZONE_REFUSE`). When it warns, tell the person a reboot is due; when it refuses, stop and tell them, and never raise the levels to get past it. After a crash, read `/Library/Logs/DiagnosticReports/panic-full-*.panic` first: its `panicString` names the zone.
