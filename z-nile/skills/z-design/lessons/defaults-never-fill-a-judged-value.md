---
title: A default never fills in a value the rule judges
when: design
tags: [defaults, records, honour]
check: For each value a new rule judges (a model, an effort, an owner), can a default fill it in when the person forgets to type it (an environment variable, the session's own model, the last value used), and is that default the judged thing's own value, or the recorder's?
---
A rule that judges what a person records guards against forgetting. A default that fills a forgotten value from the recorder's own context turns exactly that slip into a pass. The default looks harmless because it is right for the common case, and wrong only where the rule bites.

**Why:** c0306 design review 001 F5 (2026-11-14). `Effort:` defaulted to `CLAUDE_EFFORT`, the lead's session effort. Effort is judged only for `grok-` ids, and a grok review never runs at a Claude session's effort. So a lead at `xhigh` who recorded a grok review that ran at `high`, and forgot `--effort`, recorded `xhigh`, and `done` passed it. The same design had already removed the model trap (a typed `--model` wins over the measured one).

**How to apply:** take a default only where it is the judged thing's own value (here `CLAUDE_EFFORT` for a `claude-` id, whose subagent runs at the session's effort). Elsewhere, refuse the record when the rule would judge the missing value, and add a case that sets the default and leaves the value out.
