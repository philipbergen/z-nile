---
title: A narrowed promoted spec is pinned whole
when: design
tags: [acceptance, narrowing, golden]
check: When a chore narrows a promoted spec, does its acceptance pin the whole narrowed file (a normalised golden or digest), so that any edit outside the intended hunks, a deleted assertion included, turns it red, and do the Implementation steps check the pinned file's base and stop when it has moved? And can joining two lines, or changing the spaces inside a string, change what the pinned file asserts while its normalised text stays the same? Does the mutant set include "join a line onto the comment above it"? And does every raw read of the pinned file in the spec (a search, a mutant builder) go through the same normaliser as the digest?
---
Text probes for the narrowed lines miss every other way the file can be weakened: an assertion deleted from an untouched case, a loop emptied, a comment hiding code. A narrowing chore's outcome is usually "nothing else changes", and only a pin of the whole file checks that.

**Why:** R0045 design review 1 (F1): c0128's checks pinned the case titles and probed each narrowed guard, and a mutant that deleted an assertion from an unnarrowed case passed every check.

**How to apply:** pin the narrowed file's exact text, with only item ids masked and line endings made LF, by a digest or a golden string (c0150's `narrowed.spec` is the model; c0103's collapses whitespace, which lets a check be joined into a comment unseen). Make the Implementation steps check the pinned file's base and stop when it has moved.

R0045 design review 2 (F1): a whole-file pin taken in prep ties the executor to prep's base. "If a hunk does not apply, follow the Design" can then never pass, because the executor may not edit the sequestered pin. The steps must check the base blobs before applying and escalate for a re-prep when they differ.

Normalising whitespace is not harmless: a newline ends a line comment, so a check joined onto a comment line disappears from the code with the collapsed text unchanged, and the spaces inside a string are part of what a `string.find` asserts. Pin the exact text (ids masked, line endings made LF), or keep those newlines and string contents when normalising (c0150 design review 001 F3; c0103's normalisation has the same gap).

R0045 code review 001 F1: c0128's golden.spec (copied from c0103's narrowed.spec) normalised with `%s+` → space, so joining an assertion onto the `--` comment line above it turned it into a comment and every pin, the text probes included, stayed green. A whole-file normalisation of code keeps the newlines that end a line comment (or marks each comment's end before collapsing). Fixed in c0128's golden.spec by R0045; c0103's by c0156.

R0045 code review 002 F1: the fixed golden.spec's `joined()` mutant builder searched the raw file, so a CRLF checkout turned a case red while both digests passed. Every helper that reads the pinned file reads it through the same normaliser as the digest, or the pin's independence from line endings holds for the digest only.

c0153 design review 001 F1: a chore that narrowed f0032's frame case pinned it with two `string.find` probes (the helper is called; the exact compare is gone). Deleting an assertion, widening the tolerance, never asserting the result or widening the size bound each passed. Narrowing one line is still narrowing the file: pin it whole, record its base blob, and stop at step 0 when it moved.

**Also:** c0165 design review 009 F1: an override search must also cover promoted specs that pin a file by digest (they name the file as a separate string): `c0172/narrowed.spec` pins `c0114/gate-cover.spec` by SHA-256, so narrowing it with `--graph-only` broke that pin, unnamed.

**Also:** c0118 design review 012 F1: an override of a promoted spec that another item pins by digest (c0172 pins c0107 `keep.spec`) changes that digest; the new value is the digest of the reviewed text, never "what the spec prints now" (a digest re-taken from a run pins whatever the executor left, a deleted assertion included). Check: is every digest this design changes copied from a reviewed commit, and does a check fail when the file differs from the branch's merge-base file plus the reviewed hunks (and when the base or the hunks are missing)?
