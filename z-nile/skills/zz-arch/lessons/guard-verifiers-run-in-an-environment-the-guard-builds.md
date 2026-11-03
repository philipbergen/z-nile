---
title: A guard's verifier runs in an environment the guard builds, not the one it is judging
when: design
tags: [guards, environment, perl]
check: Which programs does this guard start before or without cleaning its environment, and which of their own variables (PERL5LIB, PERL5OPT, LD_*, a function, PATH) change what they print or whether they fail?
---
A digest, a start-id probe or a path resolver that runs in the caller's environment lets the caller choose the verdict: a library path makes a fake module print the pin, and an option that makes the tool die turns "cannot tell" into "holds".

**Why:** c0123 design review 010 F1: `PERL5LIB` at a fake `Digest::SHA` made the fence use the permissive hook folder (the capture's own fixture, under `bash -p` and the system `PATH`), and `PERL5OPT=-M<missing>` made an inline cleaner believe a reused pid's registry. Earlier rounds had closed a function named `perl` and a `PATH` perl one name at a time.

**How to apply:** start the verifier as an absolute program under an empty environment (`/usr/bin/env -i /usr/bin/perl …`), failing closed when it is missing; in Lune, start `env` itself, since `process.exec`'s env option merges into the parent's. Do not add the tool's variables to an unset list: the next one (`PERLLIB`, `PERL5DB`) comes next round. Cases: the tool's library and option variables against a permissive input; mutants: the inherited program back, in each place it is started.
