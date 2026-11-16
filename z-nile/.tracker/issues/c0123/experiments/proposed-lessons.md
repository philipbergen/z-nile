# Proposed lessons (c0123), one file each: the text after each heading is the whole file, for the lead to write mechanically

## zz-arch/pin-refusals-name-the-entry
```
---
title: A pin's refusal names the entry that differs, never the pin
when: design
tags: [guards, pins, usability]
check: Can an ignored file the user's tools create (`.DS_Store`, an editor backup `*~`) make this guard refuse, and does the refusal name the entry that differs (unexpected, missing, changed) without printing the value that would make it pass?
---
A content pin over a working folder also pins the ignored files in it. A guard that fails closed on a mismatch with only "refusing" leaves agents told to stop with no clue, or tempted to re-pin to get past it.

**Why:** c0123 design review 001 F3: the fence pins the SHA-256 of `z-nile/lib/git-hooks/`; an empty `.DS_Store` (ignored by `.gitignore`, so invisible to `git status`) made every fence, `check.sh` and gate refuse with `no ref guard … Stop and report this`. Review 002 F4: the first diagnosis split names on spaces and expanded `*`, so a Finder duplicate `pre-push copy` was reported as `unexpected copy`.

**How to apply:** keep the strict pin, add a names list beside it, and say what differs in whole names (walk the folder by glob, never `ls` through word splitting): `unexpected <name>`, `missing <name>`, else "a file differs in bytes or kind". Never print the pin value in a message. Add cases for an extra file, a missing file, a name with a space and a name that is a glob, each checking the message names it and does not contain the pin.
```

## zz-arch/verify-the-value-you-use
```
---
title: Verify the value you will use, not the input before the change
when: design
tags: [guards, tocttou]
check: Between the guard's check and its use, does any step (a `cd`/`pwd -P`, a link, a function call, a re-read) produce a different value than the one checked?
---
A guard that transforms a value (resolves a path, normalises a name) after checking it uses something it never checked. The gap is a race for links and, with an imported shell function, a lie.

**Why:** c0123 design review 002 F2: the fence verified an inherited hook folder, then resolved it with `$(cd "$hooks" && pwd -P)`; a `BASH_FUNC_pwd%%` function made that step name the permissive folder, and `core.hooksPath` was set at a folder the pin never saw.

**How to apply:** transform first, check the result, and use exactly that value (`res=$(cd "$cand" && pwd -P)`, then `_ok "$res"`, then `hooks=$res`). A candidate that does not transform is "not valid", never "use as given". Add a case where a stand-in for the transformer returns another value after the check, and a mutant that checks first and resolves later. Resolving is not canonicalising: on a case-insensitive disk `cd -P && pwd -P` as a shell builtin keeps the caller's letters, so a test on the result is still a test on text the caller chose (see `zz-arch/compare-canonical-spellings`).
```

## zz-test/dry-run-promoted-specs-under-the-guard-scan
```
---
title: Dry-run a sequestered spec at its promoted place under the guard scan
when: both
tags: [guards, promotion, repo-fence]
check: After every edit to a sequestered spec, was it copied to `z-nile/tests/acceptance/<id>/`, with the allow-list entries the plan names, and `tests/tooling/repo-fence.spec.luau` run, and does it pass there?
---
`./zn check` and `promote-check` run the sequestered specs and type-check them; neither runs the guard scan, which reads promoted specs for names that switch a guard off. A name added to a spec during a review round fails the gate only after `done` promotes it.

**Why:** c0123 design review 003 F1: a round-2 fix pasted a literal fence variable name into `wording.spec`, whose plan said it needed no allow-list entry; the scan would have turned the gate red at promotion.

**How to apply:** after each edit round, copy the specs to the promoted folder of a throwaway clone, add the entries the plan lists, run `repo-fence.spec` (green), then put a guarded name back into a spec without an entry (red), and remove the copies. Prefer building a guarded name from parts in a spec that only quotes it.
```

## zz-arch/allow-list-entries-are-not-caller-chosen
```
---
title: An allow-list is closed only if nothing it keeps or builds is chosen by the caller, or believed on a name the caller can set
when: design
tags: [guards, environment, allow-list]
check: For each entry the cleaner keeps or builds (a PATH directory, a config file, a name pattern, a home, a "this is our run" test), can a caller choose its value, create something that matches it, or set the variable the trust test reads, and is each such entry derived from the account database or from the cleaner's own file location instead?
---
Fixing the set of names an environment may carry is not enough if the values the cleaner then trusts come from admitted variables, from names any caller can create, or from a marker the list itself admits. Each of these gave back the escape the allow-list was meant to close, one round after the last fix.

**Why:** c0123 design reviews 005 to 008. `PATH` was rebuilt as `~/.rokit/bin:…` with `~` read from `$HOME`, so `HOME=<dir with a planted perl that prints the pin>` restored the captured escape. A folder named `pickman-stub.*` on `PATH` was kept for any caller; gating it on `PICKMAN_FENCE_REAL_GIT` moved the trust to a variable every caller can set (`PICKMAN_*` is admitted), and a forged marker plus a planted folder restored the escape again; then a path test on the folder's place was beaten by a place every agent writes (`.cache/.tmp`), by its other spelling (`.TMP`), and by a proof folder a spec left standing. `HOME` and `XDG_CONFIG_HOME` chose git's global config, which names programs (`core.fsmonitor`); git also expands `~` in config paths from `$HOME`.

**How to apply:** take the home from the passwd database (`~$(/usr/bin/id -un)`), never `$HOME`. Believe a run's own folders only inside a folder the runner registered for that run (a file the runner writes and the cleaner finds from its own location), compared by the canonical spelling the filesystem stores (`/bin/pwd -P` after `cd -P`), never by a name, a marker, a variable, a place every agent can write, or the caller's text. Nothing a spec leaves behind may count. Pin git's global config to the account's file, and refuse a moved `HOME` when that file holds a `~` path to anything but a data file. State what is left (a caller who writes into the checkout's own `.cache`, where the registry lives) as a boundary, not as an acceptance. Add cases: forged marker with a planted folder, a leftover proof folder, a link out of the registered folder, the same folder in other letters, `HOME` at a planted tree, `XDG_CONFIG_HOME`; mutants: name-only matching, containment dropped, the registry unread, `~` read from `$HOME`.
```

## z-design/migration-search-matches-built-names
```
---
title: A migration search finds the names a spec builds from parts
when: design
tags: [migration, guards, specs]
check: Does the search for the names, paths or variables a new rule drops or moves also match the ones a spec assembles from parts (`"GIT_" .. "DIR"`, a path built in two pieces), because specs split guarded names to pass the guard scan, and are the specs it finds each run?
---
A sweep that greps for the literal name misses the specs that hide it on purpose: the repository's guard scan bans some literal names in specs, so specs assemble them by concatenation. A rule that drops or renames such a name then breaks those specs and no search finds them.

**Why:** c0123 design review 007 F2. The sweep of 65 specs searched for `PATH =`, runner and `zn` copies, `fence.sh` users and inline `ac.sh` calls. `tooling/tracker-review-guards` builds `"GIT_" .. "DIR"` (the scan bans the literal), hands it through `scripts/tracker.sh` and expects the engine to refuse; the new environment cleaner drops the name, and the case failed with a fix that fitted none of the five patterns.

**How to apply:** add to the migration search a pattern for names built from parts (`grep -rlE '"[A-Z][A-Z]+_" *\.\. *"[A-Z_]+"' <tests>`), paste the command and its hits in the Design (lesson zz-review/lists-paste-their-search), run every file it finds once, and add a pattern to the fixes for what they need (here: start the engine below the cleaner, as `zn` does).
```

## zz-arch/compare-canonical-spellings
```
---
title: A path check compares the filesystem's own spelling or identity, never the caller's text
when: design
tags: [guards, paths, apfs]
check: Is every path this guard compares (a PATH entry, the checkout's root, each line of a registry) made canonical the same way in every reader, by a program that asks the kernel (`/bin/pwd -P`, `realpath`) or compared by identity (`-ef`), and does a spec spell a folder in other letters on the volume the tests run on?
---
`cd -P` resolves links, not letter case. On a case-insensitive volume (APFS, NTFS by default) `.cache/.TMP` and `.cache/.tmp` are one folder, and the shell builtin `pwd -P` hands back the spelling it was given. A guard that tests the result as text (`case $res in */.cache/.tmp/*)`) is beaten by changing one letter, and a case-insensitive `case` only moves the hole to the next equivalent spelling.

**Why:** c0123 design review 008 F1: the rule "a folder under `.cache/.tmp` is kept only if the runner registered it" was a string test on the builtin's output; `…/.cache/.TMP/pickman-stub.x`, made by an agent's own `mktemp -t pickman-stub`, passed it in both readers, and an end-to-end probe printed `ESCAPED`.

**How to apply:** make every compared path canonical with a program that asks the kernel (`CDPATH= cd -P -- "$p" && /bin/pwd -P`, the same command in the shell and the Lune reader), including the trusted root and each registry line, and refuse a result that is not one absolute line; or walk ancestors with `-ef` against the folders you trust. Prefer containment in a registered folder to a test on a name or a place. Add a case that spells the folder in other letters (guarded by a probe of whether the volume folds case, so it runs where it can differ), and a mutant that uses the builtin.
```

## zz-test/fixtures-leave-nothing-a-guard-trusts
```
---
title: A fixture removes every folder a guard would trust, passed or failed
when: both
tags: [specs, fixtures, guards]
check: Does this spec create a folder whose name or place a guard treats as the run's own (a stub, bin or guard folder, a registry), and is it removed after every case (a `pcall`, the teardown, then the error) with a last case that asserts it is gone?
---
A guard that believes "the run's own" folders cannot tell a live run's from one a spec left standing. A spec that builds such a folder under a checkout's `.cache` and never removes it hands every later launcher a trusted directory.

**Why:** c0123 design review 008 F3: `cleanenv.spec` left `pickman-guard.BBBB` and `pickman-run.AAAA/bin` under the home's `.cache` in every checkout; with that folder on `PATH` every launcher passed forged `GIT_CONFIG_*` and `GIT_SSH_COMMAND` on, and `./zn`'s own git read a forged `core.fsmonitor`.

**How to apply:** build such fixtures per case, wrap each case so the fixture is removed whether it passes or fails, end the spec with a case that asserts nothing is left, and make the guard believe only folders a runner registered so that a leftover proves nothing either way. Stubs a spec puts on `PATH` go in the run's own temp folder (`fixture.stubDir`), which the runner removes. Mutant: the teardown dropped.
```

## zz-test/pin-the-writer-of-a-trust-record
```
---
title: When a guard believes a record, a spec pins what the real writer writes
when: both
tags: [specs, guards, registry]
check: Is there a case that reads the record (a registry, a lock, a marker file) the real writer made during a real run and asserts its exact content, and a mutant of the writer?
---
Readers tested on a record the spec plants pass with a writer that records too much: the guard's decision lives in two halves, and the half that carries the user's decision is the one nobody pinned.

**Why:** c0123 design review 009 F1: every case of the allow-listed environment planted its own `tests-run.lock/folders`; changing the runner's one line to register the whole `.cache/.tmp` passed seven spec files (86 of 86) and undid the user's "Exclude .cache/.tmp" decision.

**How to apply:** read the live record in a spec (every spec runs under a live run) and assert exactly one line, equal to the canonical run folder, held by a live owner; add an end-to-end case with a lookalike beside it, and mutants of the writer (wider, narrower, an extra line). A record whose owner is gone (a killed run) proves nothing: give the readers the liveness test, and plant a dead pid instead of killing a process.
```

## zz-arch/guard-verifiers-run-in-an-environment-the-guard-builds
```
---
title: A guard's verifier runs in an environment the guard builds, not the one it is judging
when: design
tags: [guards, environment, perl]
check: Which programs does this guard start before or without cleaning its environment, and which of their own variables (PERL5LIB, PERL5OPT, LD_*, a function, PATH) change what they print or whether they fail?
---
A digest, a start-id probe or a path resolver that runs in the caller's environment lets the caller choose the verdict: a library path makes a fake module print the pin, and an option that makes the tool die turns "cannot tell" into "holds".

**Why:** c0123 design review 010 F1: `PERL5LIB` at a fake `Digest::SHA` made the fence use the permissive hook folder (the capture's own fixture, under `bash -p` and the system `PATH`), and `PERL5OPT=-M<missing>` made an inline cleaner believe a reused pid's registry. Earlier rounds had closed a function named `perl` and a `PATH` perl one name at a time.

**How to apply:** start the verifier as an absolute program under an empty environment (`/usr/bin/env -i /usr/bin/perl …`), failing closed when it is missing; in Lune, start `env` itself, since `process.exec`'s env option merges into the parent's. Do not add the tool's variables to an unset list: the next one (`PERLLIB`, `PERL5DB`) comes next round. Cases: the tool's library and option variables against a permissive input; mutants: the inherited program back, in each place it is started.
```
