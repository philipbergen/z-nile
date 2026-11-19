# Review 005: c0137 (design mode)
Inputs: branch prep-finished-claude-scans-vacuous at 4e365b632 (= origin/main merge base) plus its uncommitted diff (c0137.md, guesses.md, acceptance/scans.spec.luau, done/c0067/check.sh); c0137's check.sh; `./zn capture c0137`; zz-test SKILL.md (Sequestered); lessons zz-execute/a-finished-check-is-never-patched-on-a-guess, z-design/finished-overrides-land-before-ready, zz-test/promoted-specs-pin-rules-not-sets, z-design/restated-rules-move-together. Ran: `./zn check c0137` 3/3, `./zn check c0067` 11/11, `./zn promote-check c0137` OK; the capture's `.claude` search (hits unchanged since 0c540ce1); c0067's and c0005's 13-phrase grep by hand from z-nile/ (the only hit on main is engine/main.luau:5598); scans.spec on scratch copies (under .cache, removed) with c0067's scan mutated: M11, M12, M13 each fail the new case on an assertion; a filter on the fragment "binding commit" passes all 8 cases (F3).

The filter itself is sound: `bad=$(A | B || true)` parses as `(A | B) || true`; with no pipefail (ac.sh sets none, and `bash -c` starts a fresh shell) the status is `grep -vF`'s, so no input, all lines filtered, or a first grep that exits 2 on a missing folder all end in `|| true` exactly as the old line did (the 13-phrase scan swallowed exit 2 before too, out of scope by G2). The filter is case-sensitive and the message is lower case; d0331's prototype keeps the text on one line, so its landing leaves the filter matching. The new case reads only c0067's finished check.sh and a literal message, and nothing promoted scans `tests/` for the phrases, so promotion makes no gate rule over live text.

### F1 [high] G4 patches a finished check on a guess, and G1 merges it to main with the prep PR before the user rules
Where: c0137.md:48 (the G4 paragraph), :122 (G4), :125 (G1), :118 (Implementation step 1); `z-nile/.tracker/issues/done/c0067/check.sh:63-64`
Evidence: G4 is "Guess (prep, 2026-11-18), pending the user". G1, the user's decision, sends c0137's finished `check.sh` edits into "c0137's own prep PR, on main before z-ready", and step 1 says the edits "landed with the prep". So merging this prep PR puts the filter on main, in c0067's sequestered contract, on the agent's guess alone. The recorded decisions do not cover it: G1 is about where "the four finished check.sh edits" land, G3 is the renamed skills, and G2 ("don't widen") is the decision under which c0137.md:40 states that c0067's 13-phrase grep is left alone. zz-test (Sequestered) allows a finished check to change only for a user-decided layout move, otherwise "the executor stops and escalates", and the lesson below states guess mode "covers choices the approved contract leaves open, not edits to another item's contract". The guess is correctly marked as a guess. What is missing is anything that stops it from merging.
Critique: the tempting fix is to keep G4 a guess and let "approval before the work lands" cover it. But for c0137 the prep merge is the change to c0067's contract. There is no later landing for an approval to gate: c0137's execution changes nothing (step 1).
Consequences: holding the prep PR leaves c0067 AC10 (and c0005 AC5, F2) red on main until the user rules, and c0137 cannot be rafted meanwhile. c0067 has no `approval.md`, so no approval hash needs re-recording (the lesson's 2026-11-18 note). The option "reword the engine message" is dismissed as breaking d0331's sequestered spec, but d0331 is prepared, not finished: its own redesign may change its spec (lesson z-design/finished-overrides-land-before-ready, "Also"). That makes it a real option for the user, at the cost of reopening d0331.
Recommendation: move G4 under `## Open to the human` (or keep it as a guess and add the sentence "the prep PR does not merge until G4 is ruled"). State in the document and in the PR description that the c0067 hunk must not merge on the guess. List the options with what each costs: (a) the exact-text filter in c0067 (and c0005, F2) in this prep PR; (b) reword the message through d0331's redesign, so no finished check changes; (c) drop `engine/main.luau` from the scan; (d) AC3 stops requiring c0067 AC10 whole. Record that c0067 has no approval record to redo. Step 1 keeps its "stop and report" for a red AC3.
Lesson: zz-execute/a-finished-check-is-never-patched-on-a-guess
Erred: z-design
Upstream: none

### F2 [medium] c0005 AC5 runs the identical 13-phrase scan and is red on main for the same line; G4 neither names nor fixes it
Where: `z-nile/.tracker/issues/done/c0005/check.sh:50-54`; c0137.md:48, :122; guesses.md G1
Evidence: c0005 AC5 is the source of c0067's scan ("the 13 phrases c0005 AC5 bans"). It reads the same operands, `engine/main.luau` included, with `|| true)` and no filter. Run from z-nile/ on this tree, it prints exactly `engine/main.luau:5598: … could not push the binding commit to main …`, so c0005 AC5 is red on main for the same reason. The document never mentions c0005. If the user accepts G4 as written, the same rule ends in two states: filtered in c0067, still red in c0005. The user also rules without knowing a second finished check has the same red.
Critique: the tempting fix is to add the filter to c0005 too and call it within G4. But that edits another finished check, outside c0137's AC3 and outside G2 ("don't widen"). Adding it is the user's call as well (F1).
Consequences: if c0005 is included, the new spec case must cover both scans (PHRASES as a list of two files, each block extracted), with M11 to M13 run for c0005 too, and AC3 or AC1 names c0005 AC5. If it is excluded, the document must say c0005 AC5 stays red on main, and why. Under "findings do not become tickets", the issue has no side list to put it in, so it goes in this document.
Recommendation: put c0005 AC5 into the F1 question as a second item: "apply the same filter to c0005 AC5 (both scans pinned by the case), or leave it red, recorded here". Whichever the user picks, update E7, the Rules-and-mutants row and the Touched list to match.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

### F3 [low] The new case does not pin "exact text": a filter on a fragment of the message passes every case
Where: `acceptance/scans.spec.luau:219-239`; c0137.md:99 (rule "… and only that text")
Evidence: a scratch copy with c0067's filter changed to `| grep -vF "binding commit" || true)` passes all 8 cases. The case's plants put the banned phrase on lines that hold no part of the message, so a fragment filter (`"binding commit"`, `"could not push"`, `"rolled back"`) is indistinguishable from the exact one. But it would hide a line such as `-- after the binding commit, commit to main by hand`.
Critique: the tempting fix is to name the exact string in an assertion on the check.sh text. That pins text, not behaviour, which the Maintainability paragraph rules out.
Consequences: none beyond one plant and a mutant row.
Recommendation: add a plant in the engine fixture that holds a fragment of the message and the phrase but not the full message, for example `-- after the binding commit, commit to main by hand`, and assert it is found. Add M14 ("the filter drops a fragment of the message") to the row and to E7.
Erred: zz-test
Upstream: z-design

### F4 [low] Three statements no longer agree with the tree or with each other
Where: c0137.md:40, :62; guesses.md G1
Evidence: (1) c0137.md:40 says c0067's "other grep (line 63, the 13 phrases)" is "left out". The grep now starts at line 60, and G4 now edits it. (2) c0137.md:62 says "The three finished check.sh files change in the prep PR, G1, G3 and G4". In this prep PR only c0067's changes. c0044's and R0025's edits and the lesson sentence landed in #148 (8e6019985), as step 1 says. (3) guesses.md dates its G1 "2026-11-19" while the document's G4 says 2026-11-18 (today, Pacific).
Critique: an executor reading :62 would look for three file changes in the branch's diff and find one.
Consequences: none.
Recommendation: on :40, give the line number as 60 and add "(its operands; G4 adds a filter to it)". On :62, write "landed in the first prep PR (#148); this prep PR changes c0067's again (G4)". Align the guess date.
Lesson: z-design/restated-rules-move-together
Erred: z-design
Upstream: none

Verdict: changes
