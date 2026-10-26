---
title: Measure and gate with the tool versions the project pins
when: both
tags: [tools, versions, evidence]
check: Does `lune --version` (and every tool a measurement or gate relies on) print the version `rokit.toml` pins, or does an earlier PATH entry shadow it?
---
A shell whose PATH finds another install of a tool first (Homebrew before `~/.rokit/bin`) runs specs, mutants and measurements on a version CI never uses, so a result can hold locally and not in CI, or the reverse.

**Why:** c0153 prep: this shell ran Lune 0.11.1 from `/opt/homebrew/bin`, while `rokit.toml` pins 0.10.5 for CI. A design that rests on how Lune's JSON decoder rounds was measured on the unpinned one; re-measured with 0.10.5 it held, but only by luck.

**How to apply:** before a measurement a design rests on, or a mutant run, print each tool's version and compare it with `rokit.toml`; run with `PATH="$HOME/.rokit/bin:$PATH"` when another install shadows it, and name the version in the experiment's record.
