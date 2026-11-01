---
title: A project's promoted spec pins only its own project's files
when: design
tags: [acceptance, projects, affected]
check: Does any sequestered spec read a file of another project (a z-nile skill from a pickman spec, or the reverse), so that an edit there turns this project's gate red without the selector picking it? Is that check in check.sh instead?
---
A promoted spec runs in its own project's gate, and the affected selector picks a spec only through its requires (a file it merely reads, a skill or a tool's output, selects nothing, in any home). A pickman spec that reads `z-nile/skills/zz-test/SKILL.md`, or runs `z-nile/affected`, goes red on a z-nile change that never selects it: a graph miss found only by the next full run.

**Why:** c0170 design review 001 F4: layout.spec pinned a sentence in zz-test; review 002 F3: it also ran `z-nile/affected` and pinned its answer (a change to `z-nile/affected.luau` selects no pickman spec). Review 002 F5 corrected this lesson's first reason.

**How to apply:** pin another project's text or tool from `check.sh` (a `grep -qF` or a command through `$ZN_ROOT`, in rule form), which runs once at `done`, not from a promoted spec.
