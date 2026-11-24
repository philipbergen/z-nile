---
title: A filter given no configuration is off, not closed to everything
when: build
tags: [filter, config, capability]
check: When a filter's configuration is absent or names nothing the filter uses, does the filter switch itself off and say so, instead of refusing every item?
from: full gate of f0421-can, 2026-11-22 (#754)
---
A config file can exist for another reason and say nothing about this filter. Reading that as 'nothing is allowed' stops all work in projects with a minimal config.

**Why:** the capability filter read a models file holding only round limits as 'no CLI can deliver anything', so every worker waited; ten cases of a spec the builder had not run showed it at the gate.

**How to apply:** distinguish 'no rule given' from 'rule gives nothing'; print one line when the filter is off and why; test with a config that has only unrelated tables.
