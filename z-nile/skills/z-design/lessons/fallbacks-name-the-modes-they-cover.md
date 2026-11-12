---
title: A fallback names every supported mode that takes it
when: design
tags: [fallbacks, scope, sandboxes]
check: For each fallback ("where X is refused, keep the old behaviour"), which supported modes of running take it (the jail, an outer sandbox, CI, Linux, a plain shell), and does the Problem the issue solves still get solved in each of them?
---
A fallback written for one place ("inside the jail ps is refused, so the pid holds as before") can quietly cover a mode the issue exists to fix, and then the fix does nothing there and nobody decided that.

**Why:** R0047 design review 001 F3: c0127 read start times with `/bin/ps`, which is setuid; every `sandbox-exec` refuses it, so runs started inside Claude Code's own sandbox, where R0034's stale lock had blocked the gate, took the fallback, a narrowing with no Scope decision.

**How to apply:** list the modes the project supports, and for each say whether it takes the fallback. If a mode the Problem names takes it, find another mechanism (R0047: a non-setuid kernel read through perl) or put the narrowing to the user.

**Note (c0261 design review 010 F8):** a rule bound by an allow-list of names leaves every later mode unbound (a new review activity on a cheap model resolves without error). Bind by default and list the exceptions (`ON_THE_WAY`), so a mode added later is expensive and bound until someone says otherwise.
