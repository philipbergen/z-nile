# d0331 harvest

- note design question 1 to the user, 2026-11-14 (how many times done merges and gates again when main keeps moving; answered "Stop after 9"); avoidable, the idea added the retry and listed done's refusals without a limit (erred z-ticket): z-ticket/a-repeating-outcome-states-its-limit
- note the prototype's affected gate (E6, first run with the skill edits) failed c0111/skill-docs.spec: the reworded zz-execute step put a `./zn done` before the harvest confirmation the spec orders it after; no grep for the changed sentences found that pin, the gate on the prototype did (erred z-design): z-design/prove-specs-pass-on-a-prototype
- note design questions 2 to 4 to the user, 2026-11-14 (after design review 001: c0248's rule for a layer above a landing, the reading of "only its own commits", waiting for c0302); question 2 was avoidable, the idea did not name c0248, which designs these call sites (erred z-ticket): z-ticket/idea-settles-what-it-builds-on

Question 3 (F9) was avoidable in the idea too: the clause "holds only its own commits above it" came from the idea draft with nothing that could make it false; no separate lesson, z-ticket/a-repeating-outcome-states-its-limit's capture read (each outcome one sentence a later claim can find true or false) is the same check. Question 4 (c0302) was not avoidable at the idea: that the regression check runs a spec that fails on a layer branch came up when the check was written.
- design-review-001 F1 (erred z-design): z-design/spec-design-correspondence
- design-review-001 F2 (erred zz-test): zz-test/seed-every-enumerated-case
- design-review-001 F3 (erred z-design, upstream zz-test): z-design/guards-name-slow-tier-specs, zz-test/check-sh-never-runs-the-slow-tier
- design-review-001 F4 (erred z-design): z-design/spec-design-correspondence
- design-review-001 F5 (erred zz-arch): zz-arch/a-rollback-puts-back-what-the-commit-consumed
- design-review-001 F6 (erred zz-arch): zz-arch/a-failed-push-may-have-landed
- design-review-001 F7 (erred z-design): z-design/spec-design-correspondence
- design-review-001 F8 (erred z-design): z-design/quote-other-preps-before-promising
- design-review-001 F9 (erred z-design): z-design/never-narrow-captured-scope
- design-review-001 F10 (erred zz-arch): zz-arch/a-rollback-puts-back-what-the-commit-consumed
- design-review-001 F11 (erred z-design): z-design/restated-rules-move-together
- design-review-001 F12 (erred z-design): one-off: the runs were bounded (every one went through ./zn run --time) and only the record left it out; zz-test's Bounded commands already states the rule
- note re-prep for R0093, 2026-11-19: the --on feature (f0399's) landed after this issue was prepared and put raftBase and an eighth site (ready --on) where the fork is taken; the rebased prototype passed every own spec, and only a probe of a raft readied --on found the layer 1 forked past a landed raft's <R>/base commit (Design 1a, G2) (erred z-design): z-design/design-the-execution-window
- note re-prep for R0093, 2026-11-19: the mutation rerun on the rebased prototype found finish-diff-main-tip surviving, because main's watch capture now drops paths missing from the layer; layer-one AC1 now has main change a file both sides have (erred z-design): z-design/prove-specs-pass-on-a-prototype
- note re-prep for R0093, 2026-11-19: apply-docs.py's zz-execute step-3 anchor no longer matched after d0333 added "(steps 1 and 2)" (G1) (erred z-design): z-design/design-the-execution-window
- note the owner asked for back-and-forth design reviews (2026-11-18: "I want not just one review (no idea how that emerged) … an agent and an adversarial agent go back and forth up to 9 times"), so this re-prep's rounds from 002 are a loop of clean reviewers against z-design step 5's one-round text, as c0250's and f0417's re-preps did, stopped at the first round that approves with no finding answered fixed (erred z-design): z-design/owner-direction-over-skill-text
- design-review-002 F1 (erred z-design): z-design/reasoned-rows-claim-testable-reasons
- design-review-002 F2 (erred z-design): z-design/fallbacks-name-the-modes-they-cover
- design-review-002 F3 (erred zz-test, upstream z-design): zz-test/check-sh-judges-the-whole-spec-run
- design-review-002 F4 (erred z-design): z-design/restated-rules-move-together
- design-review-002 F5 (erred z-design): z-design/quote-other-preps-before-promising
- design-review-003 F1 (erred z-design, upstream zz-review): z-design/identify-commits-by-what-they-are
- design-review-003 F2 (erred z-design, upstream zz-review): z-design/quote-other-preps-before-promising
- design-review-004 F1 (erred z-design, upstream zz-review): z-design/restated-rules-move-together
