---
title: When pre-merge gates stop running the full suite, every spec the selector never picks gets a declaration
when: design
tags: [selection, gates, specs]
check: Which specs read files outside their requires (a folder they walk, a document they read as text) or git state no file's content shows (a clone of HEAD, ls-files, log), and does each have a declared input (a folder for a walk, `*` plus `ref:` for git state) shipped with the change that stops the full runs? When narrowing `*`, does every root and tracker read have its own line (a broad home entry does not reach a root), and is the rerun cost of every remaining `*` measured in each gate that selects it?
---
A full gate run before review used to catch every spec whose inputs the selector can't see. When the author's and reviewer's gates become affected-only, those specs run only at the merge, and a learner that records changed files can never cover files added later (a folder scanner), or state that no file's content shows (a clone of HEAD, git history).

**Why:** c0165 design review 002 F2. Two cases showed it. A new pickman Logic file didn't select `pickman/tests/meta/architecture.spec`, which walks all of `src/`. A pickman spec change didn't select `repo-fence.spec`, which scans `pickman/`. The audit then found 278 declarations to ship, and 21 specs needing an always-run entry because they clone the real HEAD or read history.

**How to apply:** audit every spec for reads outside its closure and its forcing rules. Paste the searches, ship the declarations (folder entries for walks, `*` for git state), pin the list in `check.sh`, and add a rule that new specs declare theirs.

**Also:** c0118 design review 013 F3: measure every spec the answer gives `*` (a specs that reads every project and takes over 2 s idle gets a line per registered project and a case that keeps the set complete, c0165's R73 form); the answer had timed only the cheaper of two specs.
