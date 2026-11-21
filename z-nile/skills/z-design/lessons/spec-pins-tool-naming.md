---
title: Compare a spec's folder naming with the real tool's folders
when: design
tags: [specs, naming, acceptance]
check: Does every case that pins a name an external tool writes (a folder, a file, a key) use a spelling read from that tool's real output on this machine, and does the design say which characters the tool maps, not only the ones the bug report shows?
---
A design pinned a spelling the tool never writes. Round 1 of d0328 seeded a session under `-a-b_c--worktree-x`, because the Non-goal allowed mapping only `/` and `.`. Claude Code maps every character outside letters, digits and `-`, so the spec made a wrong folder permanent and the mutant it listed was the correct behaviour.

**Why:** the repository already had the right rule (`sessionread.claudeDirs` documents it), and a directory listing of `~/.claude/projects` shows it at once. The design read only the bug report's example.

Apply: before a case seeds a folder or key under a name, list the real folders the tool writes and check the spelling against them; where the repo already reads that name, reuse the repo's own statement of the rule, and say in the design which characters the rule maps.
