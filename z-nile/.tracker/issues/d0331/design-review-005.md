# Design review 005: d0331

Mode: design. Narrow, final confirmation round. Scope, set by the lead: (1) the Scalability sentence that answers round 004's F1, checked against the prototype's `layergit.layerOneBase` (`experiments/prototype.patch`) and Design 1a; (2) the E12 record against the rest of d0331.md. Nothing else was reviewed. No probes were run.

Inputs: prep worktree `prep-d0331-r2` with its uncommitted prep changes (d0331.md lines 115 and 152 in particular); `experiments/prototype.patch`; `check.sh`; design-review-004.md and design-refute-004.md.

Checked and sound:
- Scalability (d0331.md:115). The prototype's `layerOneBase` calls `raftBase`, returns it unchanged when it is not `"main"`, returns `onto` with no `firstTip`, and otherwise runs `mainFork` (a `git merge-base`) and one `git log -1 --format=%H --fixed-strings --grep=<baseSubject> <fork>..<firstTip>`. That is the cost the sentence gives: one `git log --grep` over layer 1's own range. It applies to plain rafts too, since a plain raft's `raftBase` is `"main"`. The patch adds exactly seven `layerOneBase` call sites: `startLayer`, `finish`, `stack`, the trace skeleton (two calls), `done`, and `ready --on`. That matches "the seven `main.luau` and `layergit` sites" here, the Rules line at d0331.md:118, and Design 2's table, where `traceProblems` is "the same". "It reads no ref" is true of the guard: the grep reads the layer's commits, never `<R>/base`, as Design 1a says. The only refs `layerOneBase` reads come through `raftBase`, which every site already called before this change, so the claim adds no cost.
- E12 (d0331.md:152). The rerun on `proto-d0331-r2` at 95f18b8d9 is the commit round 004 recorded as byte-identical to `experiments/prototype.patch`. It reports the gate passed (affected), 1110 passed and 0 failed over 178 spec files, with `f0399/on` and `f0399/land` green, which supports `Overrides: none` (d0331.md:161). `./zn check d0331` passed 15 of 15, and `check.sh` has exactly AC1 to AC15. promote-check is OK. No other line of the document states a gate count or a check count that disagrees: E6's 778 and 137 is an earlier, labelled run.

No findings.

Verdict: approve
