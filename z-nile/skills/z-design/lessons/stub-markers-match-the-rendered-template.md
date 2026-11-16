---
title: A marker that tells stubs from real designs must be checked against the template the tool renders
when: design
tags: [guards, templates, existing-work]
check: Does `./zn new` render a document that meets this marker, and which promoted specs drive the guarded command on such a document?
---
A guard that exempts "stubs" protects only the rules it gates, and only if the marker really separates stubs from designs. The issue template already holds every heading a design has, so a heading is no marker; a data row in a table the template renders empty is. Check the marker against the document `./zn new` writes (read from the tree), and search the promoted specs for fixtures that write the marker. A rule that refuses a bad input is not gated by the marker: check it against every promoted fixture that plants that input to test an older refusal.

**Why:** c0181 design review 006 F1 and 007 F1: the rules were gated on the "### Rules and mutants" heading, which `./zn new` puts in every document, so the promoted specs that create issues and move them to prepared would have been refused.

**How to apply:** add a spec case that renders the real template and expects the marker to be absent; paste the search for fixtures that meet it.
