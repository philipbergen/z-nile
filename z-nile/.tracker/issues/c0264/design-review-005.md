# Review 005: c0264 (design mode)
Inputs: prep worktree at 81dded29 with the uncommitted c0264.md, check.sh and experiments/readme.patch (the rewritten scope); acceptance/intent-ac1..3.spec.luau; design-review-001..004, design-refute-001..004 and harvest.md (context only: they reviewed the earlier, smaller scope). The new capture is `git show origin/capture-workers:z-nile/.tracker/issues/c0264/c0264.md` (2e282833). The Problem equals it, plus one `Scope decision (user, 2026-11-07)` line and one `Decided with the user (2026-11-07)` line. `./zn capture c0264` still prints the old one-line capture. The captures of c0175, c0248, c0249, c0250, c0253, c0257, c0260, c0261, c0262, c0263 and c0265 were read from origin/capture-workers. Prototype: `.cache/rev5b-c0264`, a clone of the worktree with the issue folder copied in, readme.patch applied, and c0263.md and c0265.md copied from origin/capture-workers, committed as `@example.invalid`. `./zn check c0264` gives 10/10. The Design's blocks and check.sh's heredocs agree line for line (each heredoc line, labels set to `*captured*`, found with `grep -xF` in c0264.md). The promoted specs that name the README (`grep -rlF README <home>/tests/acceptance` in every home) are the twelve of AC10, plus pickman c0002 `affected-place`, which uses the root path `README.md` as selector input and is unaffected. In-flight preps' specs that read `z-nile/README` (grep over every `.worktree/*/z-nile/.tracker`) pin no heading order, no `### Roadmap` neighbour and no Intent text. The exception is c0260's (F2).
Restart of the count: this is round 1 of the rewritten scope. No finding from 001 to 004 is repeated or dropped by id.

Scope fidelity: the title gains only spelling ("README states z-nile's intent"). The Problem gains only the two allowed lines. The Intent's three outcomes each have a bullet, held by AC2 and AC4. The nine "How it should work" outcomes each have a sub-section, held by AC5 and AC6. The roadmap gains every new ticket (AC7). The diagram does not (F1).

### F1 [high] The diagram does not gain c0263, a new ticket, and AC8 passes a README without it
Where: c0264.md Problem ("The roadmap table and the diagram gain the new tickets."); Design "Diagram lines"; check.sh `DIAGRAM`, AC8
Evidence: the capture commit 2e282833 creates c0260, c0261, c0262, c0263 and c0265 ("New: capture interview, model tiers, full-force review, provenance, README intent, heartbeat"), besides c0264 itself. The seven diagram lines name c0260, c0253, c0261, c0262, c0253 and c0265/c0249. None names c0263. The prototype README's diagram has no `c0263`, and AC8 passes on it (10/10), because AC8 checks only the seven literal lines.
Critique: a captured outcome is only partly met, with no `Scope decision` line. The tempting fix is one more literal line, which leaves "the new tickets" undefined, so the next reader can't tell whether c0257 and c0175 (rows, no diagram line) are omissions too.
Consequences: an eighth line changes the mermaid block, so E4's parse has to be rerun. AC8's label and count change ("eight lines"), along with the Design and check.sh together. Defining "the new tickets" also says why c0257 (created 2026-11-05) and c0175 (2026-10-31) get rows but no diagram node.
Recommendation: add a diagram line for c0263, for example `who["provenance: idea, design approval, unblocked by: c0263"] -.-> stack`. Say in the Design that "the new tickets" are those created by the capture commit (c0260, c0261, c0262, c0263, c0265), and that c0257 and c0175 are rows only, because they were amended, not new. Make AC8 also check that each of those five ids appears in the diagram block, so that a lost line fails even if the literal list shrinks. Add mutant M10, the c0263 line removed, which fails AC8. Rerun E4.
Lesson: z-design/never-narrow-captured-scope

### F2 [medium] AC7 fails a correct c0264 when c0260 lands first, and c0260's prep, in flight, appends its own c0260 row. "Theirs to reconcile" is false for that order
Where: Design "Siblings" ("a roadmap row another PR adds for the same ticket makes AC7's row set differ and is theirs to reconcile"); check.sh `roadmap_rows`
Evidence: `.worktree/prep-capture-interview-and-idea-review` (668c9819) has a prototype that adds `| capture interview and idea review (`capture/`, `zz-review --mode idea`) | c0260 | exists |`. Its spec `c0260/acceptance/skills-restated.spec.luau` requires only "a c0260 row" (`"\n| [^\n]*| c0260 | %a+ |\n"`). On the prototype, I appended that row after c0264's rows: `AC7 FAIL ... roadmap rows differ`, 9/10. c0264's executor cannot edit its sequestered AC7, so if c0260 merges first, c0264 cannot be delivered. If c0264 merges first, c0260's prototype appends a second c0260 row, and c0260's own spec stays green with the duplicate.
Critique: the collision is concrete, not hypothetical, and the Design hands it to a sibling whose spec can't see it. The tempting fix, "c0264 lands first", is an order no `depends_on` enforces.
Consequences: a tolerant AC7 has to read the merge base (exact-checks-compare-against-the-merge-base), so that a sibling's row counts only if it was on main before c0264's change. It also needs a rule against duplicates.
Recommendation: make AC7: "each of the seven ids has exactly one roadmap row; an id that had a row at `git merge-base HEAD origin/main` keeps that row (its own PR's), and every other id has the Design's row with its true state". Implementation step 1 then says: "skip a row whose ticket already has one". Add spec cases: a sibling row on the base passes; a duplicate row fails; a missing row fails. Put the constraint into c0260's documents through its lead: when c0264 has landed, change the existing row instead of appending. Record that in c0260.md, and quote it here.
Lesson: z-design/quote-other-preps-before-promising, z-design/exact-checks-compare-against-the-merge-base

### F3 [medium] The Intent's "A person comes back only for a block" goes beyond the capture and contradicts three statements the same README adds. Its step list also has the worker "raft" a raft it has already taken
Where: Intent bullet 2 ("A worker takes a raft, ... delivers it one ticket at a time: raft, ready, run, review, gate, merge. ... A person comes back only for a block."); sub-sections Rank and lost work, The board app, Provenance
Evidence: the capture says "All human interaction moves up to the idea and design stages", and nothing about a block being the only return. The same patch adds three human acts after design:
- "z-raft asks for a rank when it makes a raft" (c0249);
- the board app "reorders by drag and drop, which sets the rank" (c0257);
- Provenance records "who set the rank" (c0263's capture, "And so on").

Rafting comes after design, and the Intent puts "raft" on the worker's list. So either a worker asks a person for a rank, which is a return that is not a block, or a person ranks by hand, which is outside idea and design. The Design's conflict list, (1) to (3), does not name this. The step list also starts with "raft" after "takes a raft", and "ready" is a raft step, not a per-ticket one, although the sentence says "one ticket at a time".
Critique: the README must not decide an open tension, and this sentence decides it ("only for a block") against the user's own rank request. The tempting fix is to reword it as "only for a block or a rank". That decides it the other way.
Consequences: removing the sentence changes AC4's text only, since AC2 and AC3 hold. Whether ranking counts as human interaction outside idea and design is for the user, and probably for c0249's prep too.
Recommendation: drop "A person comes back only for a block." from the Intent. Name it in the Design as conflict (4): the rank asked when rafting, and drag-and-drop reordering, against "all human interaction at the idea and the design". It is decided by no one here and goes to the user with c0249's lead. Fix the step list so that it matches the lead-in: either the worker starts from prepared issues and rafts them ("raft, ready, run, …"), or it takes an existing raft ("ready, run, review, gate, merge, one ticket at a time"). Pick the one the captures support, c0253's "picks up a raft: the first claimable one", which means the latter. Rerun AC4 and M5.

### F4 [medium] Older README lines labelled with the same tickets now contradict the new sub-sections, and the Intent's gloss covers only design. Round 4 already found two holes in the gloss
Where: README (main) line 36 (`worker end: any AI CLI, headless`), line 38 (`./zn work: claim top item, run next step`), line 50 ("takes the next item from the stack and moves it forward: design, raft, …"), line 54 ("every issue and raft gets a `rank:`"), line 55 ("The next item is the lowest rank …"), line 83 ("takes the next unblocked item that does not depend on the blocked one"); the Intent's last sentence; the Design's follow-up list
Evidence: the new sub-sections say:
- "A person starts any CLI by hand … It picks up a raft" (c0253), where line 50 has the worker take the next item, headless;
- "A ticket or raft may carry a rank, and unset is the lowest", and lost work comes first (c0249, c0265), where lines 54 and 55 give every item a rank and order by rank alone;
- "the raft is marked blocked … picks up the next raft" (c0250), where line 83 has it take the next unblocked item.

Each older line is labelled with the same ticket. The gloss only reinterprets "a worker design" in Autonomous delivery and the worker end. The follow-up list covers c0252, c0249's `claimable`, c0254's `preparing`, the dispatcher's design step and the gloss. It does not cover c0253's item-versus-raft worker, c0250's item-versus-raft block, or c0249's mandatory-versus-optional rank. A reader of the intent document gets two workers and two orders.
Critique: design-review-004 F1 and F3 already found holes in this mechanism: an untracked list, and a gloss that quoted text the README doesn't contain. This is a third hole in the same mechanism, the gloss reading old lines one at a time, so the mechanism is the problem. Rewriting the old lines is ruled out (they are the other tickets' text). Enumerating more glosses would grow the list each time a capture changes.
Consequences: a general reading rule decides nothing new if it states only chronology: the 2026-11-07 additions are dated later than the older Problems in the same captures ("Added by the user (2026-11-07)"). The Intent's last sentence changes (AC4), and so do the mutants that pin it. The follow-up list grows by three. The owner who drops the gloss must then drop the general rule.
Recommendation: replace the gloss's enumerated clause with one rule: "Where an older line below and a sub-section added for the 2026-11-07 ask name the same ticket and differ, the newer sub-section follows that ticket's current capture, and the ticket's own PR rewrites the older line." Keep the design-approval reading as a second clause, or fold it in. Add to the follow-up list:
- c0253: lines 36, 38 and 50;
- c0250: line 83;
- c0249: lines 54 and 55.

Add a mutant that drops the rule (AC4 fails).
Lesson: z-design/restated-rules-move-together

### F5 [medium] The Prerequisite depends on a branch whose id rename collides with two preps in flight under the old ids, and the check cannot express the other outcome
Where: Design "Prerequisite"; Implementation steps 1; check.sh `norm` and `labels_true` (`c[0-9]{4}`)
Evidence: on origin/main, f0263 (`preparing-lucky-heron-toucan`) and f0265 (`preparing-marble-walrus-walrus`) are claimed and in prep. `.worktree/prep-work-heartbeat` is at f0265 review round 2 (b52c965c), and main carries `f88d903d tracker: spend f0265 design-review`. `.worktree/prep-ticket-provenance` has `f0263/acceptance/provenance.spec.luau`. origin/capture-workers branched at 33156793, behind main (main's counter is `issue 267`, the branch's `issue 266`), and renames `f0263/` and `f0265/` wholesale. Landing it conflicts with those preps' folders. If the coordinator keeps the f ids instead, `./zn find c0263` finds nothing (AC6 and AC7 print "missing"). A text rewritten to `*captured* (f0263)` is also never normalised or checked, because both regexes match only `c`. No item tracks the landing, and an executor has no stop rule for it.
Critique: the issue cannot be executed until a coordinator's choice that nothing records. The tempting fix, widening the regex to `[a-z][0-9]{4}`, is cheap, but it still leaves the texts naming ids that may not exist.
Consequences: the decision belongs to the coordinator and the user (rename the in-flight preps, or keep the f ids). Either way, it fixes the ids in four texts (the worker, Blocked, Rank, Provenance), two roadmap rows and the diagram.
Recommendation: escalate to the coordinator: confirm that the rename lands, and how the f0263 and f0265 preps follow it. Record the answer as a `Decided with the user` line. Make Implementation step 1 a hard stop: "`./zn find c0263 && ./zn find c0265` both print a path, else post BLOCKED and stop". Widen `norm` and `labels_true` to `[cdf][0-9]{4}`, so that a relabelled text is still checked. Add a mutant: a label on an f id with the wrong state fails AC6.

### F6 [low] Three statements go a step past their captures or name the wrong source
Where: The full-force final review; The board app; The worker, z-work
Evidence:
- c0262's limited view excludes "design reviews, refutes, harvests, PR comments or worker notes". The README says "none of the reviews", which also excludes code reviews, a point c0262's capture leaves open.
- c0257's order is "lost work first, then rank, with unset ranks last and the ticket number as the tiebreak". The README says "as Rank and lost work describes", which also brings in "an item that is blocked … is skipped" for a display. Line 84 of the same README says "The board lists blocked items first".
- "The worker itself runs on a cheap model" comes from c0261 ("an orchestrating loop (the worker, c0253) runs cheap"; c0253's "It is cheap (c0261)"), but it is labelled only c0253.

Critique: each one asserts slightly more than its ticket, or credits the wrong ticket for a rule.
Consequences: AC5's text changes, and so do the labels AC6 reads.
Recommendation:
- Write "none of the design reviews, refutes, harvests, PR comments or worker notes".
- Spell out c0257's order: "lost work first, then rank, unset last, the ticket number as the tiebreak".
- Add "the cheap worker *captured* (c0261)" to the worker's labels.

### F7 [low] Cross-issue loose ends: the follow-ups still don't exist, and f0263's README criterion becomes vacuous
Where: Design "Decided with the user … Follow-up edits (captured separately by the coordinator)"; `.worktree/prep-ticket-provenance` `f0263/acceptance/provenance.spec.luau:342`
Evidence: no issue since c0266 (`classified-spec-znile-features`) exists on main, and none quotes the option (b) decision. f0263's spec checks only `has("z-nile/README.md", "provenance")`. c0264's roadmap row "ticket provenance: author, …" satisfies it, so f0263's README criterion passes without f0263 doing anything. E1 to E4 also do not say they ran through `./zn run`. E4 ran "in a throwaway dir outside the repository".
Critique: design-review-004 F1's refute moved the capture to the coordinator, which is fine only if it happens before this PR merges.
Consequences: none for c0264's text.
Recommendation: before `design: ready`, list the follow-up ids in the Decided paragraph, or note that the PR waits on them. Report the f0263 vacuity to f0263's lead. In Unknowns, record that each experiment ran through `./zn run --time …`.

Candidate lesson (for the lead to harvest): a document that restates other tickets' captures should check every in-flight prep of those tickets for a row or line it also adds (`grep -rhE '^\+\| .*\| <id> \|' .worktree/*/…/experiments`), because two appends of one row make whichever lands second fail its exact check. Check: does any sibling's prototype add a row or line for an id this design also adds?

Verdict: changes
