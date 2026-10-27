---
title: A guard's "no" is one explicit answer
when: design
tags: [security, guards, fail-closed]
check: Which outcomes of this guard lookup lead to the unguarded action, and is each of them one explicit "no" answer, with every other outcome (a missing file, a parse error, a missing function, a crash, an unexpected output) treated as "guarded"? When a guard call's failure is tolerated, does the waiver test for the condition that makes it safe (the jail itself), and which of the variables the call reset are still in force?
---
A guard lookup that treats "it didn't say yes" as "no" fails open for every failure nobody listed. Patching it case by case (the file is missing, then it doesn't parse, then a function is renamed) never ends, because each new failure is another way to read as "no".

**Why:** R0043 design review 001 F1: after the guards moved into `z-nile/lib/`, the publisher closed only the case where `fence.sh` was missing. A `fence.sh` that failed to source, or a renamed `pickman_guarded`, still read as "no check is running", so the tracker would have published from inside a check run.

**How to apply:** make the unguarded answer a distinct, positive output (a word on stdout with exit 0), act on it only when it is exactly that, and count everything else as guarded. Add spec cases for a broken, a function-less and an other-answer guard, each publishing nothing, and a mutant that goes back to "anything but yes".

**The same rule for waivers.** A waiver for "the jail refused this write" must test for the jail (the runner's markers), never for "the guard failed", and must never hide the guard's stderr. A guard function that can fail partway must not leave the guards it inherited weaker than before it ran: put its read-only refusals before its first change to the environment, set the replacement guards whole once it starts changing them, and put the writes that may be refused last. c0120 design review 002 F1: the home fence ran the full `pickman_fence` and waived any failure in a spec run. A symlinked `.cache` then ran silently, and `pickman_fence`'s early return had already unset `GIT_CONFIG_COUNT`, so the ref guard was off and `git update-ref` reached the real repository. Pin the order with cases: a refusal that holds in every mode, a waived failure whose guards equal the unwaived ones, and a refused call that leaves the inherited guards as they were.

c0139 design review 003 F1: a waiver for "not applicable here" tests the condition on disk and in the environment (no `.git` entry, no inherited git variable), never the wording of a tool's error: git prints "not a git repository" for a corrupt HEAD, a pruned worktree, an unreadable `.git` and an inherited `GIT_DIR`, as well as for a folder outside any repository. Check: can a real but broken or redirected checkout produce the message this waiver matches? Keep one predicate for the condition, shared by every caller (the guard and audit).
