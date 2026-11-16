---
name: design-first-pass-checklist
description: "Defects the adversarial design review found again and again in R0039 (5 rounds, 29 findings); check a design for them before the first review round"
metadata:
  node_type: memory
  type: feedback
  originSessionId: f5088dd0-0278-4073-8cdf-25ad806b8e83
  modified: 2026-10-20T18:14:24.880Z
---

When designing a raft (ticket-prep), run these checks on the draft **before** the first review. In R0039 (Linux spec jail) the reviewers found the same classes of defect round after round; most were avoidable.

1. **Run the promoted specs against the new world.** For every promoted spec in the touched area (`tests/acceptance/c0058`, `c0078`, `tests/tooling/*`), ask "does it still pass under the new mechanism, nested and unnested?" Round 1 found four red promoted specs, and the first Overrides line named only one. Grep for the assumptions (pid 1, `/dev/shm`, lock files), not just the file names.
2. **Name the real lifetime owner.** Before attaching state (a lock, a pid file) to a process, say which process outlives which. R0039's lock sat on the top process, but the launcher outlives the jail.
3. **Isolation: list every channel, not the one you thought of.** Filesystem, network, pid, IPC, session/process group, TIOCSTI, and host Unix sockets (a read-only mount does not stop `connect()`). Round 1 found the socket hole; round 2 found the leftover gap under the home folder. State the residue and where it is tracked, in the same words in every document.
4. **Order of operations in argv or setup is a rule.** `--remount-ro /run` before the binds under `/run` made some checkouts unjailable. Pin the order in a spec and run it on the real target.
5. **A new fallback path becomes the normal path** on some hosts. Check what the fallback writes (probe files in the real checkout) and who runs it.
6. **Every Design behaviour needs a Rules row and a spec case** (round 1 F8: escapes probes, pidns wiring, trial argv). Do the row-by-row pass yourself.
7. **Pure seams: pin the inputs, not only the function.** Round 3 and 4 kept finding that which candidates were passed in (PATH split, HOME, the checkout) was unpinned, so the pure function tested fine and the wiring was wrong. Pin the call site's arguments too.
8. **Nothing in a spec may write the real repo when it runs unjailed.** The prep itself left a blob in the shared `.git/objects`. Probe only in a clone under `$TMPDIR` until the guards exist.
9. **Gate scans run on the PR, not in `promote-check`.** Work out the repo-fence NAMES/ALLOWED entries at prep, and check that banned names don't collide with your own sequestered specs.
10. **Environment assumptions: prove them on the real target in prep.** The first CI run showed bubblewrap fails on Ubuntu 24.04 until the AppArmor sysctl is lifted. Every experiment run on the actual runner paid off; local reasoning missed it.
11. **Read your own documents for stale text** before submitting: later rounds (3, 4, 5) were mostly contradictions between the issue, the specs and the experiments (an AC saying `true`, a missing Test plan case, a step omitting an argument). One consistency pass over the AC list, Test plan, Rules table and Implementation steps removes them.
12. **Unprovable "same as before" claims.** If the Design says an output stays byte for byte, a spec must say so.

**Why:** R0039 took all 5 rounds and 29 findings (6 high in rounds 1 to 3). Rounds 1 and 2 held the real design flaws; rounds 3 to 5 were mostly wiring and stale text.
**How to apply:** at step 3 of ticket-prep, walk this list against the draft, and report in the prep handoff which items changed the design. Related: [[tracker-prep-workflow]].
