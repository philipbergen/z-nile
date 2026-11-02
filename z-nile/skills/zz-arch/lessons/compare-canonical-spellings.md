---
title: A path check compares the filesystem's own spelling or identity, never the caller's text
when: design
tags: [guards, paths, apfs]
check: Is every path this guard compares (a PATH entry, the checkout's root, each line of a registry) made canonical the same way in every reader, by a program that asks the kernel (`/bin/pwd -P`, `realpath`) or compared by identity (`-ef`), and does a spec spell a folder in other letters on the volume the tests run on?
---
`cd -P` resolves links, not letter case. On a case-insensitive volume (APFS, NTFS by default) `.cache/.TMP` and `.cache/.tmp` are one folder, and the shell builtin `pwd -P` hands back the spelling it was given. A guard that tests the result as text (`case $res in */.cache/.tmp/*)`) is beaten by changing one letter, and a case-insensitive `case` only moves the hole to the next equivalent spelling.

**Why:** c0123 design review 008 F1: the rule "a folder under `.cache/.tmp` is kept only if the runner registered it" was a string test on the builtin's output; `…/.cache/.TMP/pickman-stub.x`, made by an agent's own `mktemp -t pickman-stub`, passed it in both readers, and an end-to-end probe printed `ESCAPED`.

**How to apply:** make every compared path canonical with a program that asks the kernel (`CDPATH= cd -P -- "$p" && /bin/pwd -P`, the same command in the shell and the Lune reader), including the trusted root and each registry line, and refuse a result that is not one absolute line; or walk ancestors with `-ef` against the folders you trust. Prefer containment in a registered folder to a test on a name or a place. Add a case that spells the folder in other letters (guarded by a probe of whether the volume folds case, so it runs where it can differ), and a mutant that uses the builtin.
