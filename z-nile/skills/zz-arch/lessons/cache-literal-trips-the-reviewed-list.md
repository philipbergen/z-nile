---
title: A `.cache` text in engine code trips the reviewed-writers list, even as a field access
when: build
tags: [cache, guards, lint]
check: Does new engine code contain the text `.cache` anywhere that is not a reviewed write into `.cache/`, including a field access such as `t.cache`, which c0077's reviewed-list spec matches as text?
---
c0077's spec scans engine sources for the text `.cache` and requires every match to be on its reviewed list of writers into `.cache/`. It matches text, not meaning, so a table field named `cache` read as `t.cache` fails it like a real path.

**Why:** c0175's prototype (2026-11-15), reported by its author. Prototype code that read a field named `cache` as `t.cache` failed the reviewed-list spec, and `t["cache"]` passed.

**How to apply:** read such a field as `t["cache"]`, or name it otherwise. Add a real write into `.cache/` to the reviewed list, as the spec asks.
