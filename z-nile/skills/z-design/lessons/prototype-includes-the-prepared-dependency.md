---
title: Prove claims about a prepared dependency on a prototype that holds its edits
when: design
tags: [prototype, dependencies, pins]
check: When this design builds on a prepared or in-flight item (a depends_on) that edits the same files, was every claim that the dependency's pins still hold run on a prototype carrying that item's quoted edits, with its own specs and check functions run on it?
---
"The other item's pins hold" is a claim about a merged tree that does not exist yet. A prototype cut from main lacks the dependency's edits, so the claim is reasoned, not run, and a word-for-word pin (a README row, a step label) can break the day the two land.

**Why:** c0260 design review 003 F4: c0247's README pins were quoted from its document; the prototype replaced those lines instead of extending them.

**How to apply:** apply the dependency's quoted edits to the prototype first, extend rather than replace its pinned text, and run its `docs.spec` and `./zn check <id>` there.
