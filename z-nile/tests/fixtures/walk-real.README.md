# walk-real.served.json

A frozen copy of three real tickets (c0306, c0250, c0394) as the approval facts served them on 2026-11-23, for the
renderer's fidelity test (`tests/tooling/app-md-real.node.js`). It is never edited, with one substitution: the word
"audit" stands where the ticket text had the old name of the zz-review skill (twice), because the c0115 guard forbids that
name in any live file. The fidelity test compares the rendered output with this file's own text, so the substitution does
not matter to it.
