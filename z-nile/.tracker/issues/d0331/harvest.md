# d0331 harvest

- note design question 1 to the user, 2026-11-14 (how many times done merges and gates again when main keeps moving; answered "Stop after 9"); avoidable, the idea added the retry and listed done's refusals without a limit: z-ticket/a-repeating-outcome-states-its-limit
- note the prototype's affected gate (E6, first run with the skill edits) failed c0111/skill-docs.spec: the reworded zz-execute step put a `./zn done` before the harvest confirmation the spec orders it after; no grep for the changed sentences found that pin, the gate on the prototype did: z-design/prove-specs-pass-on-a-prototype
- note design questions 2 to 4 to the user, 2026-11-14 (after design review 001: c0248's rule for a layer above a landing, the reading of "only its own commits", waiting for c0302); question 2 was avoidable, the idea did not name c0248, which designs these call sites: z-ticket/idea-settles-what-it-builds-on

Question 3 (F9) was avoidable in the idea too: the clause "holds only its own commits above it" came from the idea draft with nothing that could make it false; no separate lesson, z-ticket/a-repeating-outcome-states-its-limit's capture read (each outcome one sentence a later claim can find true or false) is the same check. Question 4 (c0302) was not avoidable at the idea: that the regression check runs a spec that fails on a layer branch came up when the check was written.
- design-review-001 F1: z-design/spec-design-correspondence
- design-review-001 F2: zz-test/seed-every-enumerated-case
- design-review-001 F3: z-design/guards-name-slow-tier-specs, zz-test/check-sh-never-runs-the-slow-tier
- design-review-001 F4: z-design/spec-design-correspondence
- design-review-001 F5: zz-arch/a-rollback-puts-back-what-the-commit-consumed
- design-review-001 F6: zz-arch/a-failed-push-may-have-landed
- design-review-001 F7: z-design/spec-design-correspondence
- design-review-001 F8: z-design/quote-other-preps-before-promising
- design-review-001 F9: z-design/never-narrow-captured-scope
- design-review-001 F10: zz-arch/a-rollback-puts-back-what-the-commit-consumed
- design-review-001 F11: z-design/restated-rules-move-together
- design-review-001 F12: one-off: the runs were bounded (every one went through ./zn run --time) and only the record left it out; zz-test's Bounded commands already states the rule
