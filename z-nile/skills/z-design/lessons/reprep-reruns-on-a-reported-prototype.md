---
title: A re-prep re-runs the design's specs on its prototype re-ported to today's main
when: design
tags: [prep, prototype, drift, specs]
check: When a prep reopens a design prepared earlier, does its prototype still apply to main, and has the prep re-ported it and run every sequestered spec on the re-port, so that fixture drift (a gate main gained, such as the idea stage or approval at ready) and code drift (a check main moved into a shared module) are found now rather than by the executor, who cannot edit those specs?
---
A prepared design ages while it waits. Main gains gates that its fixtures do not meet, and moves the code its Design names. Its sequestered specs then fail for reasons that have nothing to do with the issue. Its executor cannot edit them, so the raft stalls at its first check.

**Why:** c0161's re-prep (2026-11-14 and 15, for c0306's design review F3). The narrow edit, a `Model:` line in two specs, would have been readied as it was. Running the specs on its prototype re-ported to main showed three more problems:
- every fixture claim was refused by main's idea stage;
- `review-read`'s rafts lacked the approvals main's `ready` now requires;
- the prototype's `ready` check sat in a code path main had replaced with `readycheck`, `readyfacts` and `workread`, which `work next` shares.

**How to apply:** at a re-prep, apply the prototype to today's main (three-way, in a throwaway worktree), resolve it, and run every sequestered spec on it, one file at a time. Fix the fixtures' drift in the specs, re-port the prototype as a new `experiments/` patch, and say in the Design where any moved check now lives and which readers it reaches.
