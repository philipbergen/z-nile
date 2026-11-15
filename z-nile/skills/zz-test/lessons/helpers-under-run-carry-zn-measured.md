---
title: A long-lived helper started under `./zn run` carries `ZN_MEASURED=1`
when: design
tags: [spend, bounded, helpers]
check: Does every process this design starts under `./zn run` (a loop, a beater, a periodic child) have ZN_MEASURED=1 in the environment of `./zn run` itself, and does a case read it from the start?
---
`./zn run` records each finished run into the checkout's spend buffer unless `ZN_MEASURED` is already set when it starts, so a helper that lives an hour adds an hour of measured wall to the ticket in focus.

**Why:** c0275 design review 001 F4: the beater and the dispatcher's per-interval child would have inflated `spend.d` rows; only the gate and the spec runner set the variable, so no proof could see it.

**How to apply:** set it in the environment of the runner (not of the command it runs: the runner decides at its start) and have the fake start of a spec record it.
