---
title: Read the installed CLI's own strings, and try a loopback provider, before marking its behaviour "not determined"
when: design
tags: [cli, experiments, quota]
check: Before an experiment about a CLI's quota, retry or error behaviour is marked "not determined", have its changelog and error strings (`strings` on the binary) been read, and has it been pointed at a loopback fake provider that answers 429 or a quota error at no quota cost?
---
A real quota error cannot be provoked on demand, but the CLI's binary names its own words, retries and caps, and a loopback provider can return any error for free. Marking the experiment "not provoked" leaves the design guessing at words the binary already holds.

**Why:** c0175 design review 001 F5 (2026-11-15). E3 and E5 stopped at "not provoked". The binaries showed that opencode retries a 429 silently, up to the provider's `retry-after`, so a long wait ends as a stall. They also showed agy's 30 s wait, and the words `resource_exhausted`, `exhausted your capacity` and `free usage exceeded`, which `adapters.QUOTA` lacked. The specs' agy quota line was invented.

**How to apply:** run `strings` on the binary and grep for the error and retry words. Point the CLI at a loopback provider for each error the design handles, and record the real text.
