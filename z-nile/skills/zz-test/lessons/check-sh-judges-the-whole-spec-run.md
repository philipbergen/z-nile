---
title: A check.sh that judges named cases of one spec run also fails on any failing case no criterion names
when: both
tags: [check-sh, mutants, specs]
check: Run each Rules and mutants row's mutant through `./zn check <id>`, not the spec alone: does it go red? And does the check.sh fail when a case it doesn't name fails, or when the spec gains a case no criterion names?
---
A check.sh that runs a spec once and has each criterion require its listed cases to pass ignores every case it doesn't list. A case added to the spec and to the Test plan but not to check.sh then guards nothing: its mutant fails the spec and passes `./zn check`, which is what `done` and the reviewer judge.

**Why:** c0132 round 3 added two cases (each half of "unread") with their rows M17 and M18, mapped them to AC2 in the Test plan, and never named them in check.sh. Both mutants failed the spec and passed `./zn check c0132` 7/7 (design review 003 F1). The mutation runner ran the spec, not the check.

**How to apply:** make the helper judge the whole run: a failing case that no criterion names fails every criterion, and so does a spec case no criterion names (set-up and clean-up excepted from naming). Read the named set from the check.sh itself, so it can't drift from the criteria. Run the mutation check through `./zn check <id>` and record that it did.
