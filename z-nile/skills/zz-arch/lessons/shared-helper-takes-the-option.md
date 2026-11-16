---
title: When a caller needs a variant of a shared writer, the writer gets an option, not a copy of its steps
when: design
tags: [tooling, helpers, atomic-writes]
check: Does the new code compose a temporary name, a chmod and a move around a shared write helper that already makes the temporary file and renames it, and would one option on the helper (checked by its own spec) do the same job in one step?
---
`z-nile/lib/replace-file.pl` creates an exclusive, uniquely named sibling and renames it. Code that makes its own name first (`mktemp`), writes through the helper onto that name, sets the mode and moves it again repeats the helper's steps, opens a window in which the file is not what it should be, and trips every scan that polices the primitives.

**Why:** c0189's first install was `mktemp`, `sh.writeReplacing`, `chmod 755`, `mv -f` so that the hook was executable when it replaced the old one. The re-prep (after c0194's scan flagged `mktemp`) gave `replace-file.pl` a leading `--mode=<octal>` option and `sh.writeReplacing` an optional mode: one rename of a complete, executable file, 12 fewer lines in the command, and the exclusivity pinned by c0077's existing spec.

**How to apply:** read the helper before composing around it. Add the option as a leading flag (an environment variable can be set by accident for every caller), keep the default, refuse bad values before writing anything, and give the option its own spec cases and mutants.
