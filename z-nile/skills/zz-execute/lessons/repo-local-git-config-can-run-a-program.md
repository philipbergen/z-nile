---
title: List the repository-local git config keys that run a program
when: both
tags: [security, git, config]
check: For each git write in a repository we do not control, is there a list of the repository-local config keys that can run a program (remote.<name>.uploadpack, core.sshCommand, filter drivers, credential helpers, includes, transport helpers), each proved refused or overridden by an option that wins?
from: f0428 review 002 F4 (2026-11-21)
---
Blocking hooks is not "no code runs". The repository's own config can name programs for fetch, push, filters and credentials.

**Why:** f0428 review 002 F4 (2026-11-21): a `-c` pin did not override `remote.<name>.uploadpack`; only `--upload-pack` did.

**How to apply:** write the key list in the design, and for each key add a case that plants it in a fixture repository with a program that leaves a marker, then runs the write and asserts no marker. Prefer a command-line option over a `-c` pin, and check the pin actually wins.
