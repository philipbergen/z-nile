---
title: A safety gate and an identity parser are two readers
when: both
tags: [parsing, safety, remote, reader]
check: When one function both decides whether an input is safe and works out what it means, has it been split, so that making the parser accept more forms can never make the gate accept more inputs?
from: code and spec reviews of #744 to #748 and d0434, 2026-11-21 (filed in #749)
---
A parser grows: each new accepted form is a convenience. A gate must only shrink. When they are one function, every convenience widens the gate.

**Why:** f0428 step 2 (2026-11-21): the remote-address reader was the safety check and the owner/repository parser. Accepting scp-like and ssh forms for identity also let those forms through the safety check that had refused them. Split into CheckAddress (safety, strict) and ParseRemote (identity, runs only on what the gate passed).

**How to apply:** the gate runs first and alone; the parser takes only gated input. Each has its own table of cases, and the gate's refusals are tested through the public entry point.
