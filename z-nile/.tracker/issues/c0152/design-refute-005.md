# Refute 005: c0152 (design mode)

- F1: fixed: new case "main moves an item the PR doesn't touch, then a spend row at its old folder: never ok". The probe pushes `tracker: done c0902` during trial 1, then a first spend row at c0902's old folder during trial 2. Result: a no, never ok. On the reduced spec, Y5 (always the PR's copy) fails this case and Y6 (always main's copy) fails the F2 case: both killed. The live-item Rules row names both. Consequences: none (the prototype already behaved right).
- F2: fixed (E7):
  - The prototype with its three specs at their promoted path ran on Linux CI through `z-nile/ci-verify.sh` from a throwaway branch. First run (40438552924): green, but merge-check.spec was the slowest spec (320.4 s) and the z-nile gate took 919.8 s against main's 660–669 s.
  - Fixed without dropping a case: the six loop cases run on a second PR head whose stage list is lighter (the probe, audit and check-paths); the stage-judging cases keep the full list. Seeding less of the tree wouldn't help, because the stages read the real items.
  - Second run (40440230252): green, z-nile 1252/1252, gate 727.6 s, the spec no longer among the three slowest (under 104 s). Locally on 0.10.5: 74.4 s, 20/20.
  - Scalability's stale timing is replaced by these figures.
  - Preparing the CI branch found two more defects, both fixed in the spec:
    - promoted, c0152's own specs match stages.spec's search, so stages.spec now excludes `z-nile/tests/acceptance/c0152/**`, with the reason;
    - a detached auto gc in the fixture's origin raced a push ("unable to write file ./objects/…"), so auto gc is now off in the fixture's three repositories.
- F3: fixed: Scalability gives the measured table for checks of 180 s, 600 s and 1200 s (moved 23/44/52%, spend-only 12/17/15%, a new trial 11/27/38%, a PR merge in the window 3/10/16%), with the command. Under load, 27–38% of checks run a second trial and 10–16% end in a no; that still converges. Consequences: none.
