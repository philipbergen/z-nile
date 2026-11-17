---
title: A trace cell cites the proof of its own claim, not whatever --check accepts
when: build
tags: [trace, final-review, citations]
check: For each test cell of the trace, does the cited line itself name the case or the `check "ACn:` of the row's own claim, and would `./zn trace --check` still pass if that line belonged to another claim? And is a row that is no claim (a lead-in, a "None." section) filled with its doc line and a note saying so, not an invented proof?
---
`./zn trace --check` matches a test cell loosely: a case is found only when its `it("...")` title sits whole on the cited line (or by a `:: <name>` cut at the first comma or semicolon and applied to every reference in the cell), and a `check.sh` reference passes on any command line. So the strongest case for a claim can be uncitable while a line of another criterion passes, and the skeleton derives rows that are no claim (a Problem lead-in ending in a colon, the "None." under Judged and Observed).

**Why:** R0121 final review 001 F1 and F2: the reviewer first cited AC5's `check.sh` line for another row and `--check` accepted it; the cases pinning a bad prefix, bad revives and "revives never rank" open `it(` on their own line with commas in the name, so neighbouring green cases of the same specs were cited instead. The tooling fix was withdrawn by the user on 2026-11-16 (c0301, c0347; zz-review/withdrawn-findings-stay-withdrawn), so the filler of the trace is the author's and reviewer's to keep honest.

**How to apply:** cite a case whose title is whole on the cited line, or `:: <name>` alone in its cell; cite a `check.sh` line only as the row's own `check "ACn: ...` line; fill a non-claim row with its doc line and a note ("not a criterion; the tool derives a claim from it"); and say in the review which proofs the matcher could not cite.
