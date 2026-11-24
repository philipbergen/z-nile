---
title: check.sh runs a fixture-heavy spec once
when: build
tags: [check-sh, speed, fixtures]
check: Does a ticket's check.sh run each slow, fixture-building spec file once and read every acceptance line from that one run, instead of once per acceptance criterion?
from: code and spec reviews of #744 to #748 and d0434, 2026-11-21 (filed in #749)
---
A spec that builds git fixtures costs tens of seconds. Run once per criterion it multiplies the gate's time and its load on the machine.

**Why:** d0434 (2026-11-21): the check.sh first ran the fixture-building restack spec more than once; it now runs it once and reads each criterion from that output.

**How to apply:** run, keep the output, grep it per criterion.
