---
title: Adding a worker CLI adds its agent marker in the same change
when: both
tags: [cli, authority, agents]
check: Does every name in `models.CLIS` own a marker in `agentenv.OWNERS`, and does a spec fail when one does not?
from: f0421 escape note, 2026-11-24
---
A person-only act (approve, consent) refuses a session by its agent marker. A CLI with no marker is taken for a person.

**Why:** escape in f0421, 2026-11-24: agy was added as a worker CLI (#766) without its marker, so `./zn approve` did not refuse an agy session. Fixed by adding `ANTIGRAVITY_AGENT` to `agentenv.OWNERS` (which now names the CLI each marker belongs to; `MARKERS` is built from it) and a spec that fails when a CLI owns no marker. The spec runner also clears the new variable (`fence.CLI_VARS`), or c0369's approve specs, which clear markers by hand, would refuse themselves when a gate is run from an agy session.

**How to apply:** when a CLI joins `models.CLIS`, add its marker to `OWNERS`, add it to the runner's cleared variables, and run the person-only commands once with only that marker set, on a terminal.
