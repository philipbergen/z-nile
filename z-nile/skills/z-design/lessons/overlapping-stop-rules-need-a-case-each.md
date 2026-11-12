---
title: When two rules can end the same loop, a case makes the other unable to fire
when: design
tags: [mutants, rules, loops]
check: For each rule that stops or refuses, does a case remove the facts of every other rule that would also stop it (moving the worktree, not deleting it; deleting the memory while main still shows the claim) and assert the rule's own words?
---
A mutant of a rule survives when another rule produces the same outward behaviour: a worktree deleted takes its memory with it, and a given-back claim restamps main.

**Why:** c0275 prep (2026-11-12): mutation runs of the beater's "worktree gone", "memory gone" and "session" rules survived until the cases moved the folder (the log follows the open file), deleted only the memory, and ended only the session.

**How to apply:** for each stop reason write the case in which it is the only one true, and assert the text it says. A proof that changes a fact to stop a background process first waits until the process has made its first observable action (the loop reads the fact; a process still booting is refused at its start and never reaches it).
