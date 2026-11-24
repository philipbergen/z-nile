# walk-real.served.json

A frozen copy of three real tickets (c0306, c0250, c0394) as the approval facts served them on 2026-11-23, for the
renderer's fidelity test (`tests/tooling/app-md-real.node.js`). It is never edited, with one substitution: the word
"audit" stands where the ticket text had the old name of the zz-review skill (twice), because the c0115 guard forbids that
name in any live file. The fidelity test compares the rendered output with this file's own text, so the substitution does
not matter to it.

## units-real.served.json, themes-real.served.json, units-real.expected.json (slice 2)

The units index and the theme facts of this repository as the Go reader served them on 2026-11-24 (582 units: 291 done, 151
backlog, 17 active, 13 retired, 7 closed, 103 withdrawn), frozen once from the one-time real chain (`tests/chain/units-chain.sh`,
`ZN_CHAIN_KEEP`). The text of every unit but four open ones was taken out (the link rules read ids, kinds and states, and the file
was 415 KB); one substitution was needed for the c0115 guard (it forbids a path through the `.claude/skills` link in any live file): in the preview of one open unit the words `.claude/skills/<skill>/lessons/` became `<skills folder>/<skill>/lessons/`; nothing else was changed. `units-real.expected.json` holds the
counts the page must give for the three frozen tickets of `walk-real.served.json` against that index: 392 id mentions, 389 links,
3 marked as not in the index (all `c0020`, an example), 21 tributary names left plain by the common-word rule, and `c0261` resolving
to the withdrawn stub with its date and subject. The counts were checked against an independent oracle (`oracleOf` in
`app-md-real.node.js`, a regular expression with lookarounds over the source, which shares no code with the page's link rules)
and agree. The files are never edited.
