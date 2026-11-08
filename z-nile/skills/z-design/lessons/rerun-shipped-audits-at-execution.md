---
title: An audit shipped as data is rerun on the tree the PR merges into
when: design
tags: [audit, declared-inputs, migration]
check: Does an Implementation step rerun the audit command (the search that produced the declared inputs or allow-list) on the merged origin/main just before the PR, and does a check fail on any hit that is neither declared nor excluded, with every audited item (kept or excluded) keyed to the content that was audited, so a later change to a kept item is caught too, and are the reviewed lists out of the executor's reach?
---
A design that ships the result of an audit (declared inputs, an allow-list) freezes the tree as it was when prep ran. The tree keeps growing between prep and the merge, so the data goes stale.

**Why:** c0165 design review 007 F1: E9's audit of which specs read outside their requires dated from 2026-10-28; by prep's re-run 57 more spec files had landed and 20 matched the audit's search with no declaration, so a pass would be reused after the doc they read changed.

**How to apply:** record the search command in the issue, add an Implementation step that reruns it against the merged `origin/main` before the PR, and make a check.sh criterion fail on any hit outside the declared set and a reviewed exclusions list.

**Also:** c0165 design review 008 F1/F2: the exclusions were keyed to the audited blob but the declared specs were not, so c0184's rewrite of five declared specs would have passed; and the reviewed lists sat in a folder the executor may edit.

**Also:** c0165 design review 009 F2: an audit chosen by a text search over each spec's own lines misses one-line wrapper specs and reads made in helper modules; cover every spec path (a `nohit` line keyed by path for the ones the search does not match) so a new spec file turns the check red until someone reads it.

**Also:** c0118 design review 012 F2: a re-prep on a moved main reruns every gate rule main gained since the first prep, not only the audits the first prep shipped (c0165's declared inputs landed between c0118's two preps: its new `real.spec` read every project's tracker and declared nothing). Check: which gate rules landed between the first prep's base and the re-prep's, and does the design meet each?
