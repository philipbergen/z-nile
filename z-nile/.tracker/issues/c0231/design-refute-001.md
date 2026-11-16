# Design refute 001 (c0231)
Answers to design-review-001.md. Nothing was executed in this round; every fix below is written, not run, 2026-11-15, and is recorded in the document's "Changes after design review 001".
- F1: fixed: `;;`/`;&`/`;;&` become single separators and `checkText` tracks `inPattern`; specs for `yes|y)`, `"yes"|n)`, the here-document form and the case-body refusals added; consequences: AC8 (c0191 boundcmd.spec) re-run by the executor for the separator change; new Rules and mutants row.
- F2: fixed: `mutate.sh.txt` rewritten to work in a `.cache` copy, find the specs by fallback, and count a kill only on a failed assertion; consequences: the 19 recorded kills came from the old script and stay cited as such; the executor re-runs all 22 once.
- F3: fixed, local to yes (`skipRedirects`); the reviewer allowed this choice; consequences: other rules keep today's behaviour, stated in the Design; spec cases added.
- F4: fixed: allow-list kept and recorded as judgement call 4; header comment and zz-test paragraph to state the exception; pinned by a new AC7 case; consequences: `consumers.spec` rm -i / git add -p cases unchanged.
- F5: fixed in part: `after` carried into `sh -c` and `eval`; group forms and odd here-document words named as limits in zz-test (AC7); consequences: groups stay refused, documented.
- F6: fixed: reasons restated; no spec change.
- F7: fixed: reason reworded, clusters and abbreviations counted as negative, two-three spec cases added; a huge count remains a named limit; consequences: none.
- F8: fixed: three rows and mutants M20 to M22 added (reasoned, written not run).
- F9: fixed: the Solution detail cites R0079 review-001 F3; the spec header (refused.spec) updated; the captured Problem is left as captured.
