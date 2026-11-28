# Design refute 003

- F1: fixed: `bounded.pl`, `cpu.sh` and `measure.pl` are in the setup case's copy list, and the case asserts that stderr has no `bounded:` line; E5 ran the mechanism on a scratch fixture (exit 0 with the three files, exit 2 with `bounded.pl` alone; `-u` makes the child see `PARENTVAR=nil`, without it `c9999`) and marks the mutant row `run` at the mechanism; consequences: the full case waits for the implementation, as every case of this file does.
- F2: fixed: How it lands step 2, Implementation step 7 and the moved-main rule run `z-nile/check.sh --slow` after the full gate, one after the other, and rerun both on a `yes`; AC8's claim, the `ac8slow` comment, the slow list's header and the lesson note now say `--slow` at the merge; the pass is Observed (OC1); consequences: one extra run of about 7 minutes at the merge.
- F3: fixed: 47 cases in 34 files (46 in z-nile, 1 in pickman): 38 in `rewrite-list.txt`, 9 in `rewrite-list-slow.txt`; consequences: none.
