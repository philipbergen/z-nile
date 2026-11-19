# Proposed lessons from the c0189 re-prep (for the lead to write; a subagent writes none)

Each section is one lesson file under the named skill's `lessons/` folder: the fenced block is the whole file. Where the lesson is a new source for an existing one, the section says so and gives the note to add.

## z-design/peers-scans-run-on-the-prototype
```
---
title: A prepared peer's repository-wide scan runs on the prototype before the design is called done
when: design
tags: [coordination, sequestered, scans, prototypes]
check: Which prepared or in-flight issues have a sequestered spec that scans the whole tooling or every skill (for a primitive such as mktemp, for a sentence, for a path), and has each been run on this prototype, stacked with that peer's own prototype.patch, with every red case either fixed here or a named interface?
---
A scan reads every file, so "independent in code" proves nothing about it. A design written while a peer was still a draft can add the one line the peer's finished scan forbids, and no member's own gate shows it.

**Why:** c0189's install called `mktemp` (design review 003 F4 had added it, correctly, for a unique name). c0194, prepared later, sequestered a scan of the tooling for `mktemp`; R0070's coherence review (F2) found c0194's `callers.spec` red on c0189's line, and the raft had to unfold c0189 for a re-prep. The same review found c0189's pinned prototype rule sending a clone "into $TMPDIR or the scratchpad" against c0194's decided `.cache/.tmp/` (F1): both pins passed, the combined text contradicted itself.

**How to apply:** `git worktree list` and `ls .tracker/issues/*/acceptance` for every prepared peer; apply this prototype and each peer's `experiments/prototype.patch` in one scratch clone (`git apply --3way`, keep both sides of a text conflict) and run the peers' scans and doc specs there. Read the merged paragraph against each peer's captured Problem, not only against the pins. Prefer removing the flagged primitive (here, by teaching the shared helper an option) to an allow-list entry in a peer's sequestered spec.
```

## z-design/quote-other-preps-before-promising (new source, not a new file)
Note to add to the existing lesson: c0189 re-prep (R0070 design review 001 F1): a rule pinned in three skills sent a scratch clone to `$TMPDIR` or the scratchpad while c0194 (prepared later) had captured and decided `.cache/.tmp/` ("It needs to be a sub of pickman"). The draft was written when c0194 was a draft and the two Existing-work notes pointed at each other; when the later prep finishes, the earlier prepared design that states the same fact is re-read against it, and a conflict reopens that design, not a note under it.

## zz-arch/shared-helper-takes-the-option
```
---
title: When a caller needs a variant of a shared writer, the writer gets an option, not a copy of its steps
when: design
tags: [tooling, helpers, atomic-writes]
check: Does the new code compose a temporary name, a chmod and a move around a shared write helper that already makes the temporary file and renames it, and would one option on the helper (checked by its own spec) do the same job in one step?
---
`z-nile/lib/replace-file.pl` creates an exclusive, uniquely named sibling and renames it. Code that makes its own name first (`mktemp`), writes through the helper onto that name, sets the mode and moves it again repeats the helper's steps, opens a window in which the file is not what it should be, and trips every scan that polices the primitives.

**Why:** c0189's first install was `mktemp`, `sh.writeReplacing`, `chmod 755`, `mv -f` so that the hook was executable when it replaced the old one. The re-prep (after c0194's scan flagged `mktemp`) gave `replace-file.pl` a leading `--mode=<octal>` option and `sh.writeReplacing` an optional mode: one rename of a complete, executable file, 12 fewer lines in the command, and the exclusivity pinned by c0077's existing spec.

**How to apply:** read the helper before composing around it. Add the option as a leading flag (an environment variable can be set by accident for every caller), keep the default, refuse bad values before writing anything, and give the option its own spec cases and mutants.
```

## z-design/depends-on-inherits-the-dependency-raft
```
---
title: A new depends_on waits for everything the dependency's raft waits for
when: design
tags: [coordination, dependencies, rafts]
check: When this design adds a depends_on on an issue that sits in a readied raft, what does that raft wait for (its Order), and does its executor's prompt edit my document and so turn the grouped hash of a raft holding it stale?
---
A dependency is on the whole chain behind it, and a step in the other raft's prompt that edits this issue's document invalidates an earlier raft grouping.

**Why:** c0189 re-prep, design review 007 F1, F2: depends_on: [c0194] meant waiting for R0078 and R0070 too, with c0123 behind; c0194's step 8 adds a note under c0189.md, so c0189 may only be rafted after R0070 is done. The order itself was the user's (G5).

**How to apply:** read the dependency raft's Order and Implementation steps before adding the edge; name the chain and the rafting rule in Risks; put the order to the user as a guess.
```
