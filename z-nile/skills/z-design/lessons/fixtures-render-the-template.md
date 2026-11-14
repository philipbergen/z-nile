---
title: A fixture that stands in for a template file renders the template
when: design
tags: [fixtures, templates, check-sh]
check: When a command runs a file every item gets from a template (a raft's check.sh, a prompt), does the spec's fixture use the rendered template rather than a stub such as `true`?
---
A stub hides what the real file does: a raft's check.sh runs every member's check.sh and promote-check, so a stub of `true` lets a command pass that no real raft can.

**Why:** c0248 design review 001 F2: `done --through` passed its specs with a raft check.sh of `true`, but every real raft's check.sh ran the blocked member's checks too and refused the early landing.

**How to apply:** render the template into the fixture (the same substitution `ready` or `new` does), and add one case whose member check fails where the command must still pass.
