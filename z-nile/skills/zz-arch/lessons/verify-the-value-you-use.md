---
title: Verify the value you will use, not the input before the change
when: design
tags: [guards, tocttou]
check: Between the guard's check and its use, does any step (a `cd`/`pwd -P`, a link, a function call, a re-read) produce a different value than the one checked?
---
A guard that transforms a value (resolves a path, normalises a name) after checking it uses something it never checked. The gap is a race for links and, with an imported shell function, a lie.

**Why:** c0123 design review 002 F2: the fence verified an inherited hook folder, then resolved it with `$(cd "$hooks" && pwd -P)`; a `BASH_FUNC_pwd%%` function made that step name the permissive folder, and `core.hooksPath` was set at a folder the pin never saw.

**How to apply:** transform first, check the result, and use exactly that value (`res=$(cd "$cand" && pwd -P)`, then `_ok "$res"`, then `hooks=$res`). A candidate that does not transform is "not valid", never "use as given". Add a case where a stand-in for the transformer returns another value after the check, and a mutant that checks first and resolves later. Resolving is not canonicalising: on a case-insensitive disk `cd -P && pwd -P` as a shell builtin keeps the caller's letters, so a test on the result is still a test on text the caller chose (see `zz-arch/compare-canonical-spellings`).
