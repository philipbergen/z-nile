# Proposed lessons from the c0194 prep (for the lead to write; a subagent writes none)

Each section is one lesson file under the named skill's `lessons/` folder: the fenced block is the whole file. Where the lesson is a new source for an existing one, the section says so and gives the note to add.

## z-design/read-why-before-moving-a-guard
```
---
title: Read why a guard sits where it does before you move it
when: design
tags: [guards, history, moves]
check: For the guard, folder or rule this design moves, which review or issue put it where it is, what hole did it close, and does an experiment show the new place closes the same hole?
---
A guard's place is often the answer to an earlier finding. Moving it because "nothing says it must be there" reopens that finding.

**Why:** c0194 asked to move the spec runner's temp folder from the system temp folder into `.cache/.tmp`. A comment said "a spec's `mktemp -d` must land outside .cache" (review 004 F2). The reason was in R0210's history (`git log -S`, `review-004.md`, `refute-004.md`): nothing outside the jail may run from a folder a spec can write, and a promoted spec used `mktemp -d` as its "outside" folder. The move was possible, but only with the jail closing the rest of `.tmp`, the fixture helper refusing temporary trees, and a probe for outer sandboxes.

**How to apply:** `git log -S'<the comment's words>'`, read the review file it cites, write the hole and the spec that relied on it into the Design, and show by experiment that the new place keeps both.
```

## zz-test/sequestered-allowlists-match-fragments
```
---
title: A sequestered allow-list matches fragments, not whole lines of code that does not exist yet
when: design
tags: [sequestered, allowlist, scans]
check: Does a scan in a sequestered spec allow lines by their whole text, and will the executor's wording of those lines be the one the spec names?
---
A sequestered spec cannot be edited during execution. An allow-list keyed on the exact text of a code line breaks the day the executor words that line differently, and nothing can be done in the raft.

**Why:** c0194's `callers.spec` first listed the exact `mktemp -d` and `/tmp` lines of `tmp.luau`. A reword of one line failed the scan with nothing to edit. It now allows by a fragment per file (`"mktemp", "-d"`, `.sentinel.XXXXXX`) with the reason beside it.

**How to apply:** key allowances on a short fragment per file plus its reason; keep exact-line lists (like `cachepaths.ALLOWED`) in non-sequestered harness files the executor edits and a reviewer checks.
```

## z-design/read-back-every-prototype-edit
```
---
title: Read back every scripted edit of the prototype
when: design
tags: [prototype, edits, experiments]
check: After each scripted edit of the prototype, was the changed place read back, or a spec case run that fails if the edit did not apply?
---
A scripted replace that does not match changes nothing and says nothing. A formatter that reflows the prototype between edits makes the next literal replace miss.

**Why:** c0194 prep: a replace in the prototype's command line (print the sweep's report) did not apply after the formatter reflowed that code. The sweep deleted trees silently, and no spec case noticed until a reviewer ran it (design review 001 F4).

**How to apply:** assert the pattern is present before replacing (`assert old in text`), read the lines back after, and give the behaviour a case that fails without the edit.
```

## z-design/instructions-runnable-where-they-run  (new source, not a new file)
Note to add as a source: c0194 design review 002 F1/F2 and 003 F1. The check gains: "is a wrapper proved by running the thing it exists for (a nested runner in `./zn tmp jail`; Merging's `new` then `verify` with a session `TMPDIR` and another `ZN_TOP`), with the prototype's own committed code, not HEAD's?"

## zz-test/guard-needs-its-own-case  (new source)
Note: c0194 design review 003 F3. A command line that wraps a sandbox had no case because a sandbox cannot nest in the spec jail; a stand-in `sandbox-exec` first on `PATH` that answers only the named arguments runs the real command line inside the jail.

## zz-arch/one-reader-per-format  (new source)
Note: c0194 design review 003 F5. Owner records in run folders were written with two start-id formats and read as one; both writers and the reader now use the one perl snippet, pinned equal by a spec.

## z-design/probe-free-cli-lines-in-prep  (new source)
Note: c0194 prep. The capture's premise "`TMPDIR` moves a plain `mktemp -d`" was false on macOS; one free experiment showed it.

## z-design/accepted-risks-checked-and-decided  (new source)
Note: c0194 design review 001 F2 and 003 F2. A guess the user has not answered is never asserted by a sequestered spec, and the prep does not merge while it is open.

## zz-test/guards-move-with-the-working-directory  (new source)
Note: c0194 design review 001 F1 and 002 F4. A probe that replaces a guard asks about the folders the design now uses, as a pure list with cases, and judges "writable at all", not what the folder holds at one moment.

## zz-test/jail-allows-name-folders
```
---
title: A jail's allow rule names the folders it opens, never a pattern over names the command can create
when: design
tags: [jail, sandbox, guards, profiles]
check: Can the jailed command create a path that one of the profile's allow rules matches, other than inside a folder the profile names?
---
A sandbox profile that allows "any `.cache` folder below the tree" opens every place a `.cache` can be made, because the jailed command can create the folder itself. Allow a `subpath` for each folder that exists before the command starts (made by the caller), and deny the entry itself.

**Why:** c0194 design review 004 F1: the clone's jail allowed `^<tree>/(.*/)?\.cache(/.*)?$`, so `mkdir` and writes succeeded at `repo/.git/hooks/.cache` and `repo/z-nile/tests/lib/.cache`, against the user's decision that sources and git directory stay read-only. The sequestered spec pinned the loose regex text, so only a design change could fix it. A write probe through the real jail found it in one command.

**How to apply:** list the folders the profile opens and pass them in; assert in a spec that no allow rule is a regex over names; probe the real jail once with `mkdir` at a deep path of the sources and of the git directory.
```

## z-design/mutation-runner-runs-correct-variants  (new source)
Note: c0194 design review 004 F3. A mutation script that counts any FAIL line as a kill cannot tell a kill from a case that always fails in that environment (`runner.spec`'s `needJail` case in the jailed clone); judge each mutant against the unmutated case's failing set and record the case that killed it.

## zz-arch/one-reader-per-format  (new source)
Note: c0194 design review 004 F5. Two readers of one record disagreed on the failure path (`tmp.startOf` read "cannot read" as "no such process"); the snippet now exits 1 for "no such process" and 2 for "cannot tell", and both readers keep a process they cannot tell.

## zz-test/live-jail-case-returns-off-host
```
---
title: A case that needs the live jail returns off-host, and check.sh proves it ran
when: design
tags: [specs, jail, promotion, check-sh]
check: Under each PICKMAN_TEST_JAIL value (sandbox-exec, outer sandbox, none, bwrap), what does each case of this spec do after promotion, and what in check.sh fails if the jailed branch never ran?
---
A sequestered spec that `error`s off `sandbox-exec` keeps its own check honest, but once promoted it reddens every Linux, outer-sandbox and jailed-clone gate, including another raft's CI.

**Why:** c0194 design review 005 F1: `runner.spec`'s live case called `error` when not jailed. Promoted, it would have failed c0075's Linux CI gate (which lands after it) and every jailed clone. c0076 already had the shape: the case returns when unjailed and writes a marker when it ran, and `check.sh` requires the marker on Darwin.

**How to apply:** return after asserting which kind of run it is; write a marker under the case's own `.cache` folder when jailed; make the item's `check.sh` require the marker on Darwin ("run this check outside any other sandbox"); tell the prepared raft that lands later.
```
