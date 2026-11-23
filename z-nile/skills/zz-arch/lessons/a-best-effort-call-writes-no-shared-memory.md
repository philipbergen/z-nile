---
title: A best-effort side call writes no shared memory of failure
when: build
tags: [live, beat, cache, failure]
check: Does a call that is allowed to fail silently (a beat, a metric) avoid writing any shared 'the service is down' record that a later, required call would trust?
---
A silent best-effort call fails for reasons the required call would not (it does not start the service). If it records the failure where the required call reads, the required call gives up without trying.

**Why:** f0420 step 4b (2026-11-21, review of a fix): the beat never starts the daemon; when the daemon had idled out, the beat marked the layer gone and the worker's next real events were dropped silently.

**How to apply:** only a call that is allowed to start and wait for the service may record that it is down. Spec: service stopped, beat, then an emit, and the emit must arrive.
