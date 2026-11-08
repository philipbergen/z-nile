---
title: A "no promoted spec changes" check runs the specs that read the files, never diffs the branch
when: design
tags: [check-sh, overrides, rafts]
check: Can a raft mate's declared Override, or this issue's own promotion on `done`, turn this check red for a correct implementation? If the claim is "the edit breaks no promoted spec", does the check run the promoted specs that read the touched files (from `git grep` over the home's `tests/acceptance`, by what the specs read) instead of diffing `tests/acceptance` against `origin/main`?
---
A branch diff of `tests/acceptance` cannot say which raft member changed a file. In a raft whose other member has Overrides, a correct implementation of an issue with `Overrides: none` fails its own `promoted_unchanged`, and the issue's promoted folder trips the raft mates' identical checks. The claim an issue wants is behavioural: the promoted specs that read what it edits still pass.

**Why:** c0247 design review 001 F2: a probe gave `rc=0` for c0247 alone and `rc=1` once a raft mate's override commit was on the branch (R0077 holds c0160, which has Overrides; c0239 overrides `c0114/docs`). c0239's AC8 has the same shape and is guarded by an allow-list of its own Overrides.

**How to apply:** AC "no promoted spec changes" becomes "the promoted specs that read these files pass", with the reader list computed by `git grep -lE 'SKILL\.md|README\.md'` (the names the specs read, not the full paths) and pasted into the Regression guard; keep a diff check only where the issue itself declares the allow-list (an issue with Overrides).

c0247 design review 002 F3: find the readers by what they read, not by the files' paths alone: a spec that walks every skill (c0115 absence) reads the edited file without naming it. `git grep -lE 'SKILL\.md|README\.md'` over the home's acceptance specs found 40, the path grep 8; a mutant that adds a forbidden word to the edited file stays green with the narrow list.
