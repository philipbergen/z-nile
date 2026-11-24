# walk-real.served.json

A frozen copy of three real tickets (c0306, c0250, c0394) as the approval facts served them on 2026-11-23, for the
renderer's fidelity test (`tests/tooling/app-md-real.node.js`). It is never edited, with one substitution: the word
"audit" stands where the ticket text had the old name of the zz-review skill (twice), because the c0115 guard forbids that
name in any live file. The fidelity test compares the rendered output with this file's own text, so the substitution does
not matter to it.

## units-real.served.json, themes-real.served.json, units-real.expected.json (slice 2, refrozen in round 2)

The units index and the theme facts of this repository as the Go reader served them on 2026-11-24 (663 units: 291 done, 137
backlog, 32 active, 13 retired, 7 closed, 183 stubs of which 85 renumbered, 92 withdrawn and 6 removed), frozen from the one-time
real chain (`tests/chain/units-chain.sh`, `ZN_CHAIN_KEEP`). The text of every unit but four open ones was taken out (the link rules
read ids, kinds and states; the whole file is 454 KB); one substitution was needed for the c0115 guard (it forbids a path through the
`.claude/skills` link in any live file): in the preview of one open unit `.claude/skills/<skill>/lessons/` became
`<skills folder>/<skill>/lessons/`. `units-real.expected.json` holds the counts the page must give for the three frozen tickets of
`walk-real.served.json` against that index: 653 id mentions, all 653 links (c0020, which the first freeze marked as unknown, is now a
stub that says it was renumbered), none marked, no tributary link, 22 tributary names left plain by the rule, and `c0261` resolving to
the withdrawn stub with its date and subject. An independent oracle (`oracleOf` in `app-md-real.node.js`, regular expressions over
the source that share no code with the page's link rules) counts the same mentions. The files are never edited.
