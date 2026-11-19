---
title: A check that a name appears nowhere skips every folder records are written to
when: design
tags: [acceptance, search, records]
check: Does a "nothing names X" search exclude every folder records are written to (each `.tracker/`, every skill's `lessons/`), since harvests and reviews quote the very file a finding was about? Does it still cover skills, docs, specs, scripts and watch files? And is there a case where a record naming X passes and a skill naming X fails?
---
A sequestered check cannot change once it is prepped. If a record written after the prep names the removed file (for example a lesson harvested from a review of this item or another), the check goes red on a correct change, and the only way out is a re-prep.

**Why:** c0392 design review 001 F3: AC1's `git grep` for `lobby-start` excluded only `.tracker/` folders. This prep's harvest and f0209's both land before c0392's raft, and either was likely to write that name into a `lessons/` folder.

**How to apply:** exclude every record folder by pathspec (`:(exclude,glob)**/.tracker/**`, `:(exclude,glob)**/lessons/**`). Add a mutant where a lesson naming the file must pass, and one where a skill naming it must fail.
