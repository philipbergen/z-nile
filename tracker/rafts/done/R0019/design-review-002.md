# Review 002: R0019 (design mode)
Inputs: prep branch `prep-renumber-step-one` @ 7da618c (includes origin/main 55e94b3; `git log HEAD..origin/main` is empty); tracker/rafts/R0019/{R0019.md,check.sh,design-review-001.md,design-refute-001.md}; tracker/issues/c0052/{c0052.md,check.sh,acceptance/*.spec.luau,experiments/prototype.diff}; tracker, testing, architecture, ticket-prep and review skills.
Dropped from design-review-001: none withdrawn; F1 to F5 are all fixed as the refutation says (checked below).

Spot checks, in a scratch clone of 7da618c with `prototype.diff` applied (clean) and the `origin` remote removed:
- The three specs pass: renumber 20/20, new-spacing 3/3, skill-doc 5/5 (28, matching the documents). `scripts/tracker.sh` with no arguments prints `renumber <old> [<new>]` (RC1).
- F1: `originIds` reading `HEAD` fails 12 of 20, reading `main` fails 14 of 20, matching M13 and M14. The fixture now uses `git init -b scratch`, `commit.gpgsign=false` and asserts every git step.
- An extra mutant nobody listed, "leave the old id out of the local maximum", fails "the old id alone is the highest" (19/1), so rule 1 holds against it. Leaving the old id out of the origin side alone can't change the result, since the local tree always holds the old id.
- F2: the `Overrides:` line is there, with evidence, and `lune run scripts/affected` still prints `ALL`. A `git grep` outside tests/acceptance for `renumber`, `next free` and `multiple of 10` finds only the Conflicts bullet, which c0052 rewrites, the Numbering bullet, which `skill-doc.spec` case 5 pins and the design keeps, the main-checkout guard sentence, and the Landing references to "renumber per Conflicts", which stay correct under the new bullet. None goes stale.
- F3: the new f9999 case is there, and M15 is listed. F4: R0016 is gone from Risks, and `nextAbove` is described as not pure everywhere. F5: new-spacing has its `cleanup` case.

No new high or medium findings. Raft coherence (one issue), executability (prototype, exact signatures, error strings and usage line all given) and architecture (tooling only, no `src/` or dependency change) hold.

Verdict: approve
