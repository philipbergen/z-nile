# Trace: R0092

Commit: 

## Claims

| claim | design | test | code |
|---|---|---|---|
| c0264:P1: The z-nile README states the intent: humans at idea and design, workers carry rafts to merge, cheap on the way and sharp at the end | z-nile/.tracker/issues/active/c0264/c0264.md:81 (the Intent's five bullets) and z-nile/.tracker/issues/active/c0264/c0264.md:83-97 (How it should work) | z-nile/.tracker/issues/active/c0264/check.sh:169 (AC2, the Intent's themes) and z-nile/.tracker/issues/active/c0264/check.sh:173 (AC6, the vocabulary of the user's rules) | none |
| c0264:AC1: `## Intent` comes after the opening picture and before `## How it should work`. | z-nile/.tracker/issues/active/c0264/c0264.md:70 | z-nile/.tracker/issues/active/c0264/check.sh:168 (runs intent.spec.luau, its case AC1) | none |
| c0264:AC2: the intent names the two human stages, the worker, the full-force review, the economy and the names. | z-nile/.tracker/issues/active/c0264/c0264.md:81 | z-nile/.tracker/issues/active/c0264/check.sh:169 (runs intent.spec.luau, its case AC2) | none |
| c0264:AC3: the intent claims nothing as built: it carries no state label. | z-nile/.tracker/issues/active/c0264/c0264.md:81 | z-nile/.tracker/issues/active/c0264/check.sh:170 (runs intent.spec.luau, its case AC3) | none |
| c0264:AC4: the idea stage, the worker, models per command and activity, the full-force review and provenance are sub-sections of How it should work, each carrying a state label that names an issue (the exact ids are check.sh's, AC7). | z-nile/.tracker/issues/active/c0264/c0264.md:83-94 | z-nile/.tracker/issues/active/c0264/check.sh:171 (runs intent.spec.luau, its case AC4) | none |
| c0264:AC5: a worker clears its context and takes the next raft whenever a raft ends, merged or blocked. | z-nile/.tracker/issues/active/c0264/c0264.md:102 and z-nile/.tracker/issues/active/c0264/c0264.md:84 (both edges back to claiming) | z-nile/.tracker/issues/active/c0264/check.sh:172 (runs intent.spec.luau, its case AC5) | none |
| c0264:AC6: the README states the rules of the worker model in the user's terms (the vocabulary in check.sh), and names no tiers, no cheap/sharp/wait levels, and quotes no model names in the sections about the models to use (Intent, The idea stage, The worker, Models per command and activity, The full-force review). c0251's line in Reviews by different models is outside that list. | z-nile/.tracker/issues/active/c0264/c0264.md:99-110 and z-nile/.tracker/issues/active/c0264/c0264.md:90 | z-nile/.tracker/issues/active/c0264/check.sh:173 (vocabulary: the pinned phrases, no tiers, no model names, no overclaim) | none |
| c0264:AC7: every roadmap row and every issue-labelled sentence has the state the tracker shows for its issue; a sentence about what `main` already does carries `*exists*` with no id. | z-nile/.tracker/issues/active/c0264/c0264.md:83 (the label rule) and z-nile/.tracker/issues/active/c0264/c0264.md:96 (the roadmap) | z-nile/.tracker/issues/active/c0264/check.sh:210 (truth_and_deps: the label map, the rows, each state against the tracker, the raft's outside dependencies) | none |
| c0264:AC8: the README changes only in Intent and How it should work. | z-nile/.tracker/issues/active/c0264/c0264.md:70 | z-nile/.tracker/issues/active/c0264/check.sh:211 (others: the rest equals the merge base's README) | none |
| c0264:AC9: the workflow diagram is the reviewed one, word for word (`diagram.txt`). It shows the interview, the approval, `z-work`, lost first, one ticket at a time with its full-force review, the final review and `./zn done`, and both ways a raft ends (merged, and released when blocked) as edges back into claiming the next raft, each clearing the worker's context. | z-nile/.tracker/issues/active/c0264/c0264.md:84 | z-nile/.tracker/issues/active/c0264/check.sh:212 (drawn: a diff against diagram.txt) | none |
| c0264:AC10: no issue id has more than one Roadmap row (a promoted structural spec, `roadmap-unique`, so whichever PR lands second fails the gate). | z-nile/.tracker/issues/active/c0264/c0264.md:151 and z-nile/.tracker/issues/active/c0264/c0264.md:221 (a row stays one row) | z-nile/.tracker/issues/active/c0264/check.sh:214 (runs roadmap-unique.spec.luau) | none |
| c0264:AC11: None. | z-nile/.tracker/issues/active/c0264/c0264.md:214 (the "None." under Judged; not a criterion, the tool derives a claim from it: c0301) | z-nile/.tracker/issues/active/c0264/check.sh:216 (finish, the tally of the ten Checked criteria; no line tests a "None.", and this cell proves nothing: c0301) | none |
| c0264:AC12: None. | z-nile/.tracker/issues/active/c0264/c0264.md:217 (the "None." under Observed; not a criterion, the tool derives a claim from it: c0301) | z-nile/.tracker/issues/active/c0264/check.sh:216 (finish, the tally of the ten Checked criteria; no line tests a "None.", and this cell proves nothing: c0301) | none |

## Source files

| file | claims |
|---|---|
