---
title: A template the check accepts lets an unfilled copy pass
when: design
tags: [templates, proxies, checks]
check: When a check judges documents written from a template, does the template as shipped fail that check on its placeholders (marked so the check can find them), so that a copy with only the required names filled in is refused?
---
If the template already passes the shape check, a copy that fills in only what the check names (a hash, a list of paths) passes too, and the reader is the only guard against an empty page.

**Why:** f0339 design review 001 F6: the explainer template passed `explainer.check` with no Touched modules, so a copy with the hash and the paths set and every other placeholder kept got `ok` from `./zn explain`. The fix marks each placeholder with the class `zn-fill`, refuses a page that still has one, and refuses identical before and after diagrams.

**How to apply:** mark every placeholder in a template with one machine-readable marker, refuse it in the check, and pin "the template's only problems are its placeholders" in a spec.
