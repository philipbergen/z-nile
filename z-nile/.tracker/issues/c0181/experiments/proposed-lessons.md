# Proposed lessons for c0181 (written by the lead when the prep lands)
Each section is one lesson file: write the fenced block, without the fence, to `<skills folder>/<skill>/lessons/<slug>.md` (`z-nile/skills/<skill>/lessons/`). The sources are the `harvest.md` lines that name the id, so no `from:` is needed. The files carry no `enforced_by` or `not_codifiable` key: those keys are unknown to the parser until c0181 itself lands, and c0181's sweep gives every lesson its state (these eight are process lessons about design and review; the sweep decides whether any has a check).  The harvest already names each lesson, so no `- note` line is needed for these eight.

Notes to add to existing lessons (as the body paragraphs noted, with the harvest source already named or by a `- note c0181 …: <ids>` line in the lead's own harvest):
- `z-design/restated-rules-move-together`: a fix that changes a shared tool re-judges every plan row and criterion built on that tool (`grep -n '<tool>' <plan>`, then re-read each hit).
- `zz-test/no-vacuous-pass`: a case that pins a framework's filter or mode builds its fixture from a helper whose defaults (here `presence = true`) can short-circuit the call before the filter runs; with the filter removed, does the assertion's fixture still reach the code under test?
- `z-design/new-refusals-reach-every-caller`: a rule that refuses a bad input must be checked against every promoted fixture that drives its command, especially fixtures that plant that bad input to test an older refusal and assert its message.
- `zz-test/allowlist-keys-exist`: a baseline kept in an item's own folder must say what happens when that item finishes or is renumbered (`./zn done`, `compact`).

## z-design/full-enforcement-means-every-clause
```markdown
---
title: "Fully enforced" means every clause of the lesson's check is decided
when: design
tags: [lessons, coverage, scope]
check: Does the named check decide every clause of the lesson's check question (not only today's instances of the guard, list or record), and is a thin marker (a text or stamp that shows a mitigation is present) marked part rather than full?
---
A lesson marked fully enforced leaves every step's reading and the build index, so any clause its check leaves undecided is asked by no one. Read the lesson's `check` clause by clause. If the mechanism names specific files, modules or instances, it decides "this X" only for those, and the lesson is partly enforced unless it is about those instances alone. A text or stamp that only shows a mitigation is present (a `Cost:` line, a mutant listed in a Rules row) decides a clause of a lesson whose substance is a reading: it makes the lesson partly enforced, never fully, and it keeps the lesson out of "not codifiable" too. Do not set a floor on the fully enforced count; review judges each mark.

**Why:** c0181 design reviews 002 F4, 003 F3, 004 F4 and F5, 006 F7, 008 F1 and F2, 009 F1 and F2: the plan's F rows kept leaving a clause (a general question answered only for the guards that exist today), and a floor on the full count made the executor mislabel rows to meet it.

**How to apply:** when you classify a lesson, write the clause the check leaves in the row, and make that the lesson's remaining `check`. After any change to a shared tool a row relies on, re-read every row that names it.
```

## z-design/plans-from-readers-map-to-the-design
```markdown
---
title: A plan written by other agents must map to the design's closed sets
when: design
tags: [process, plans, delegation]
check: Does every value in the plan's hook, "where it runs", stamp-field and document-marker columns map to something the Design defines (a command, a file kind, a hook, a format), and was every row re-read after a shared tool changed?
---
Readers who classify or plan work name commands, files, markers and moments the design never built. An executor who builds from such a row must invent the command, the file kind or the marker, unreviewed, or park the lesson with a "tried" record for something never attempted. Check every closed-set column of the plan against the Design (hooks, commands, item files, stamp lines, document markers) before the first review, and send a row that cannot be mapped to the user as an option, never to a silent park.

**Why:** c0181 design reviews 006 F3 and F4: the Sonnet readers' table named a `clean` command that does not exist, `hunks.md`, `pinned.md`, a "warn" mode and gate-time mutation runs; the Design had seven hooks.

**How to apply:** grep each closed-set column of the plan for values the Design does not define; each hit is mapped, built, or listed for the user.
```

## z-design/rewrites-keep-rafted-records
```markdown
---
title: A command that rewrites other items' design files must keep rafted members' records
when: design
tags: [rafts, records, migration]
check: Does the rewrite touch any file raftplan.isDesignFile counts (a harvest.md counts), and does it run inside keepRecords like compact, remap and renumber?
---
A raft's `grouped:` line stores a hash of each member's design files. A command that rewrites one of them (a harvest ledger renamed by a lesson merge) makes `ready` and `fold` refuse the raft with no design change behind it, and the way out is an unfold, a fold and a new coherence review. Run such a rewrite inside `keepRecords`, so every entry that matched before is re-recorded, in the raft document and in its coherence reviews' `Grouped:` lines.

**Why:** c0181 design review 004 F1: `lesson-merge` rewrites the harvest.md of every item, and three backlog rafts carried records (R0053, R0054, R0062); one member's ledger alone names about thirty lessons.

**How to apply:** list the files a new rewrite changes, intersect with `raftplan.isDesignFile`, and add a spec case with a grouped raft whose member is rewritten.
```

## z-design/stub-markers-match-the-rendered-template
```markdown
---
title: A marker that tells stubs from real designs must be checked against the template the tool renders
when: design
tags: [guards, templates, existing-work]
check: Does `./zn new` render a document that meets this marker, and which promoted specs drive the guarded command on such a document?
---
A guard that exempts "stubs" protects only the rules it gates, and only if the marker really separates stubs from designs. The issue template already holds every heading a design has, so a heading is no marker; a data row in a table the template renders empty is. Check the marker against the document `./zn new` writes (read from the tree), and search the promoted specs for fixtures that write the marker. A rule that refuses a bad input is not gated by the marker: check it against every promoted fixture that plants that input to test an older refusal.

**Why:** c0181 design review 006 F1 and 007 F1: the rules were gated on the "### Rules and mutants" heading, which `./zn new` puts in every document, so the promoted specs that create issues and move them to prepared would have been refused.

**How to apply:** add a spec case that renders the real template and expects the marker to be absent; paste the search for fixtures that meet it.
```

## zz-arch/ledgers-are-history
```markdown
---
title: A check must not require an old ledger line to agree with the thing's current state
when: both
tags: [ledgers, records, gate]
check: Can the thing this record describes change after the record is written, and what does this check say then?
---
A ledger line records what was true when it was written. A gate that compares old lines with current state turns red when the state changes for a good reason, and the only fix is to edit finished history. Gate only the line's shape and that its subject exists (or was merged away); compare the content only where the line is written, for the item that writes it, in a command that names that item.

**Why:** c0181 design review 001 F4: a `- codify` harvest line recording "not codifiable" would have been compared with the lesson's state on every gate, so codifying the lesson later, or merging it, turned every gate red.

**How to apply:** for each check over a ledger, list what can change after a line is written (a lesson's state, a finding's fix, an id) and make the check ignore it, or run only for the current item.
```

## zz-test/helpers-that-trim-change-expected-strings
```markdown
---
title: A helper that trims output changes the strings a case can expect
when: both
tags: [specs, helpers, outputs]
check: Does any expected string start or end with whitespace that the helper strips (for example `git status --porcelain` through `fixture.git`)?
---
`fixture.git` trims both ends of its output, so ` M path` arrives as `M path`. A case that expects the untrimmed line fails for every implementation, and a sequestered spec cannot be repaired during execution. Compare the trimmed form, or read the untrimmed stdout through `fixture.exec`.

**Why:** c0181 design review 003 F2: an assertion that nothing changed but one file was written with its leading space and could never pass.

**How to apply:** for each helper a case reads output through, read its trim and quoting rules before writing the expected string, and run the case against a stub that does nothing.
```

## zz-test/new-fields-break-hand-built-literals
```markdown
---
title: A new required field on an exported type breaks hand-built literals in promoted specs
when: both
tags: [types, specs, wiring]
check: Which promoted specs build this type by hand, and does the gate's type stage (not tests/run) still pass for them?
---
Promoted specs build `Lesson` and `Item` tables literally. In strict mode a literal that lacks a new non-optional field is a type error, which `tests/run` never reports but the gate's Lune type stage and `./zn done` do. Make a new field optional and have every reader treat nil as empty, or the chore overrides those specs. Grep the promoted specs for literals of the type, and add a type-check line to the acceptance.

**Why:** c0181 design review 002 F1: `enforcedBy`, `distinct`, `merged` and `Item.dir` were designed as required fields, which would have broken c0111's metrics and harvest specs at the merge gate while the item's own check stayed green.

**How to apply:** `git grep -n 'lessons.Lesson\|lessons.Item' -- z-nile/tests`, then run `luau-lsp analyze` over those folders in the acceptance.
```

## zz-test/runner-copies-must-still-load
```markdown
---
title: A module the test runner newly requires must load in every copy of the runner
when: both
tags: [runner, specs, copies]
check: Which promoted specs copy z-nile/tests/run.luau with only tests/lib, lib and the .luaurc files, and does each copy still load and print as before?
---
Seven promoted specs run copies of the runner that hold only `tests/run.luau`, `tests/lib`, `lib` and the `.luaurc` files (run-record-merge, fence-leftovers, fence-inherited-env, lock-start-ids, c0127/reuse, c0120/runner-home, c0114/gate-cover). A top-level require of an engine module turns all of them red. Load a new module lazily, under `pcall`, only on the path that needs it, and let a missing module print what the runner printed before.

**Why:** c0181 design review 004 F2: the failure footer needed `codify` and `lessons`, which those copies do not have.

**How to apply:** `git grep -ln 'tests/run.luau' -- z-nile/tests` lists the copies; add a case that runs a copy with no engine and one failing spec.
```
