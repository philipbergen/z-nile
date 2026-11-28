# Design refute 001

- F1: fixed: the exemption follows into nested runs through `ZN_VACUOUS_PARENT` (Design §3 point 6), honored only inside a measured run and for a listed id; `run-guard-relaunch`'s probe is on the rewrite list; E1b reruns the measurement with a log file over both tiers; Regression guard names the class; fixture.spec and vacuous.spec gained cases; consequences: a stray variable is ignored outside a measured run (`vacuous.inherited`), a nested run prints its own off line, a nested run of a non-exempt case is checked (both pinned).
- F2: fixed: commits as `dev@example.invalid` and git add/commit go through `fixture.git`; consequences: none (the base is under the run's `.cache`); repo-fence on a copy is run in Phase 1 (lesson note).
- F3: fixed: How it lands is now a one-time procedure keyed to zz-rules Merging step 4 with exact commands, carried by z-raft's Order, the prompt and the Ready-to-merge comment; a fix-forward PR after the merge; boundcmd `TOOLING` gets the script; the merge-versus-rebase difference is Guess G2; consequences: the list is frozen after landing so no standing `--check`; restacks' AC5 red has a stated fix.
- F4: fixed: the list is `acceptance/rewrite-list.txt` (sequestered) and AC8 checks every `file :: case` from `PICKMAN_RESULTS` with `ok=true` via `acceptance/listed-cases.luau`; E4's later finds go in the Verification log, not the list; consequences: a case rename after prep needs a human ruling (rename is a failure by design); mutant row added.
- F5: fixed: Existing work names the 13 branches, and z-design step 4 and zz-test say a no-assertion failure is never an expected red (pinned by docs.spec); consequences: those two skills are touched modules.
- F6: fixed: fixture.spec gets a `pickman/` home (forwarder runner, `t` re-export, `.luaurc`) and a case from it; mutant row added; consequences: the fixture copies three more files.
- F7: fixed: docs.spec finds the one added line and requires each of the five items on it; consequences: the lesson's added line has to hold them all on one line.
- F8: fixed: AC6 requires exit non-zero and empty stdout for an unknown ref, exit 0 for answers; the repository `--gate-needed` reads is stated; consequences: none.
- F9: fixed: the helper case uses a real fixture repository under `.cache` with a succeeding and a failing command and `fixture.git`; consequences: it removes its fixture.
- F10: fixed: the coordinator builds one `workerArgs(file)` for both branches (Design §3); consequences: none; a case per branch not added (the two branches share the builder).
- F11: fixed: comment says AC5, functions renamed `ac6` and `ac8`; consequences: none.
- F12: fixed: the Design says why c0462 depends on c0455; consequences: none.
