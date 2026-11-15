# Review 007: c0264 (design mode)
Inputs: prep worktree HEAD 4f27f670 (tracker: prep c0264 answer design-review-006); c0264.md, check.sh, diagram.txt, legend.txt, acceptance/intent.spec.luau, acceptance/roadmap-unique.spec.luau, experiments/README.draft.md, README.base.md, mutants.sh, design-review-001..006, design-refute-001..006, harvest.md; `origin/main` 96e5604e after `git fetch` (c0265, c0274, c0275, c0276, c0277 on it); `origin/prep-work-heartbeat` 05263daf (c0265.md, check.sh), `origin/prep-model-tiers-cheap-sharp-wait` cd605d96 (docs.spec), `origin/prep-capture-interview-and-idea-review` f9b6bbfb; the unlanded capture branch `capture-c0265-split` (759739cc, the split's Scope decision lines).
Round 3 (the last) of the combined design. Round 2's answers hold, except where F2 and F3 below say otherwise: `README.base.md` is byte-identical to `origin/main`'s README; the six F2 pins and mutants are in check.sh and mutants.sh; the Design's Claiming bullet (F3), AC6's label and the diagram's stack node (F4) are fixed; harvest.md and spec-design-correspondence carry round 1's and 2's candidates (F5). None of round 2's findings is reopened as such.

Runs (all through `./zn run --time <s> --`; a scratch clone `.cache/rev007` of the worktree with the checkout's `origin/main` fetched in, no commits, so no identity; merge probes on plain files in my scratchpad; the clone was removed afterwards and `git status --short` in the worktree shows only this file):
- `./zn check c0264` with the draft as README: 10/10.
- Step 1 with nothing landed (`git merge-file` with ours = base): 0 conflicts, result byte-identical to the draft.
- Step 1 over each landing order E3b names (ours = base with the landed hunk, then `git merge-file ours README.base.md README.draft.md`):
  - c0261 first (the c0251 line's parenthetical reworded, as `c0261-reworded`): **1 conflict**, on that line: the draft also changes it (base line 65 → draft line 104, `what c0117 designs (*designed* (c0117))` → `what c0117 built (*exists* (c0117))`).
  - c0265 first (a `./zn lost` line in Order and a `| work heartbeat | c0265 | exists |` row after c0258): **2 conflicts**, Order (draft lines 83-87 against ours) and the Roadmap (ours' c0265 row against the draft's c0260..c0265 rows).
  - c0265 first, the Order line only: **1 conflict**.
  - c0260 first (its prototype.patch row after c0258): **1 conflict**, in the Roadmap.
  - c0261's planned bullet in The five parts: 0 conflicts.
- My mutants of the draft (perl over the draft as the clone's README, then `./zn check c0264`):
  - `limited-view-widened`: "It sees no design reviews, refutes, harvests, PR comments or worker notes, so it judges the result on its merits and not through the compromises on the way." → "It also reads the design reviews, refutes and PR comments, so it weighs the compromises made on the way.", and the Intent's "without the compromises made on the way" → "with the compromises made on the way in view": **10/10, survives**.
  - `context-dropped`: The worker loses "It keeps one context for the whole raft, so what it learned on one ticket carries to the next.", and Stacked delivery's "by the same worker, so its context carries over;" → "by the same worker, each ticket in a fresh context;": **10/10, survives**.
  - `model-name-other`: "The cheapest (grok-code-fast-1 or kimi-k2) do the waiting and the polling.": **10/10, survives**.
  - `split-labels` (a correct relabel after c0265's split: "... is lost. *captured* (c0265)", "... learns it lost the claim. *captured* (c0274)", "... a numbered copy of it continues the work. *captured* (c0277)"): **AC7 fails**, `label places differ: > Claiming across hosts|c0274` (AC6 also failed, only because my edit lowercased the pinned "A takeover").
  - `c0265-done-relabelled` (c0265's folder moved to `done/` in the clone, every `*captured* (c0265)` and the c0265 row flipped to *exists*, as step 2 says): **10/10, passes**, with the takeover and the numbered copy now labelled *exists*.
- Other preps' README plans: `git diff --name-only origin/main...origin/<b>` for every open PR branch, then `grep -F z-nile/README` in each changed file: hits only in c0261, c0265 and c0260 (as E3b says) and `R0083-project-board` changes the README itself; `prep-home-rule-reads-every-path-spelling`, `prep-full-force-final-review`, `omarchy-board-app`, `R0071-no-leaked-processes`, `prep-relevant-review-lessons`, `prep-sweeper-killed-under-load`, `R0061-z-nile-header-slug-scans`, `raft-check-guards-regroup`, `prep-merge-past-tracker-only`: 0. E3b's list is complete.
- Capture: `./zn capture c0264` prints c8c78404 with no marker; the Problem gains only detail and the three `Decided with the user (2026-11-08)` paragraphs. Scope holds, except F1's "the roadmap table ... gain the new tickets".

### F1 [high] c0265 was split on `main` into c0265, c0274, c0275, c0276 and c0277, but the README still labels the takeover and the numbered copy c0265, so a correctly labelled README fails AC7 and, once c0265's layer lands, step 2 stamps *exists* on a takeover and a copy nobody has built
Where: draft line 91 (Claiming across hosts: "... the next worker resumes it. A takeover deletes the old heartbeat branch ...; the old worker's work is kept, and a numbered copy of it continues the work. *captured* (c0265)"); line 163 (the only heartbeat row); line 165 ("The worker's tickets (c0248 to c0254, c0260 to c0263 and c0265)"); check.sh `LABELS` (`Claiming across hosts|c0265`, one entry) and `ROWS`; the Problem's c0265 Decided paragraph ("The README states the heartbeat branch and the numbered copy ..., labelled captured with c0265"); Design items 3a and the c0265 orders of E3b.
Evidence:
- `origin/main` carries `c0274` "Take over lost claim", `c0275` "Automatic heartbeats", `c0276` "Board shows lost work" and `c0277` "Discard and recover worktree" (aa4cc5ef and the commits before it, 2026-11-08 14:01), each "(split from c0265)". `git merge-base --is-ancestor aa4cc5ef HEAD` in the prep: not an ancestor, so the design was never merged with them. `grep -rn 'c027[4-7]' z-nile/.tracker/issues/c0264/`: no hits.
- The split's capture (`capture-c0265-split`, not landed yet) quotes the user: "yes go ahead and split the whole thing up and tie them togetjer in a raft so we can run through these a layer at a time in a PR". It gives c0274 "A worker that takes over lost work does so as a normal claim", "The old owner learns it lost the claim" and the user's "If a job is taken over the take over deletes the heartbeat branch and creates a new one"; c0277 "A numbered copy continues the work" and the work recovered; c0275 the automatic beats; c0276 the board; c0265 keeps "Lost work is found and listed". It sets `depends_on`: c0274 on c0265, c0275 on c0265 and c0274, c0277 on c0274 and c0275. So c0265 is layer 1.
- `split-labels` above: the README that names each part's ticket fails AC7, because `LABELS` pins one c0265 label in Claiming and no c0274 or c0277.
- `c0265-done-relabelled` above: with c0265 done (the first layer of that raft), step 2 ("Update any roadmap row or prose label whose issue has changed state") turns the one label to *exists* (c0265), over sentences that state c0274's takeover and c0277's numbered copy, both still captured. That is a README describing as built what is not, the thing the legend forbids ("Nothing below is described as built unless it is labelled *exists*").
- The Problem's captured outcome "The roadmap table and the diagram gain the new tickets": c0274 to c0277 are new worker tickets, with no row and no mention.
Critique: the README attributes the user's takeover and copy rules to a ticket that no longer carries them. This is z-design/status-labels-need-a-tracker-fact ("which file or command proves it?"): the tracker now says c0274 and c0277. The tempting fix is to add four rows and leave the bullet's one label. Then a c0265-first delivery still stamps the whole bullet *exists*.
Consequences: one label per ticket inside one bullet means more `LABELS` entries in pinned order (`Claiming across hosts|c0265`, `|c0274`, `|c0277`, and c0275 if the README says the beat is automatic). Splitting the sentence must keep AC6's pinned phrases whole ('A takeover deletes the old heartbeat branch', 'a numbered copy of it continues the work'). Four more rows mean four more `ROWS` lines, and AC10 then also guards c0274 to c0277 against a second row from their own PRs. The c0265 Decided paragraph is the user's words plus the author's gloss: only the gloss changes. The split's Scope decision is still on a capture branch, so the prep must merge `origin/main` after that capture lands.
Recommendation:
- Merge `origin/main` into the prep once `capture-c0265-split` lands.
- In the draft, give each part its own label, keeping every pinned phrase:
  - "An item in progress whose heartbeat is stale is lost. *captured* (c0265)"
  - the takeover sentence: "*captured* (c0274)"
  - the kept work and the numbered copy: "*captured* (c0277)"
  - and, if the beat sentence says it is automatic, c0275.
- Add rows for c0274 to c0277 (state from the tracker) and the ids to the closing list. Extend `LABELS` and `ROWS` to match.
- Rewrite the c0265 Decided gloss as "labelled with the ticket that carries each part since the split (c0265, c0274, c0277)". Update item 3a and E3b's c0265 order: a five-layer raft whose every layer flips only its own labels.
- Add mutants:
  - `copy-labelled-c0265`, today's single label, which must fail AC7;
  - `takeover-built-early`, c0265 done and *exists* on the c0274 sentence, which must fail AC7 (the clone moves c0265 to `done/` as above);
  - a correct variant with c0265 done and only its own label flipped, which must pass.
Lesson: z-design/status-labels-need-a-tracker-fact

### F2 [high] (repeat of review-006 F2) Two more of the user's rules can be reversed and pass all ten criteria: the full-force review's limited view, and one context for the whole raft
Where: check.sh AC6 vocabulary; Design "The user's rules the text states" ("the full-force review's limited view and redo", "the PR stack ticket by ticket in one worker"); the Problem's quotes "fed a limited view of the tickets so that it looks at it only on its merits as given and not with the broader context of all the compromise on the way" and "if we can stay in the same worker for it all so that context remains"; draft lines 29, 75, 110, 168.
Evidence: `limited-view-widened` and `context-dropped` above, each 10/10. 'limited view' is pinned, but the sentence that says what it excludes is not, so the README can say the review reads the compromises. 'each ticket is worked to completion before the next is picked up, by the same worker' is pinned, but the clause that keeps the context is not, so the README can say each ticket starts in a fresh context. Both reverse the user's words.
Critique: review 006 F2 said the pins were picked phrase by phrase and that "the next round finds a fifth". It asked for the pins to be derived from the Design's rules list, in a table: rule, phrase, deletion mutant. The answer added the six phrases that review named and no table (the Rules and mutants table still has one AC6 row listing mutants). The lesson the author wrote ("Derive the pins from the Design's list of rules, one phrase and one deletion mutant each") was not applied to this design. The mechanism is the problem: keyword pins next to a rule, not on the clause that states it.
Consequences: a pin on the defining clause catches deletion and rewording, not an added contradiction, which stays step 5's. Pinning more sentences word for word makes a landed edit by another issue (F3) more likely to break a pin. Each such pin needs the landing-order variants of F3, or a stated rule that the landed words win and the executor escalates.
Recommendation:
- Add the table under Rules and mutants. One row per item of "The user's rules the text states" and per bullet of the Problem's "How it should work describes", each with:
  - the pinned clause, which must be the clause that states the rule, not a keyword beside it;
  - its deletion or reversal mutant;
  - or "step 5 only" and why.
- At least add these pins, each with a mutant like those above:
  - 'It sees no design reviews, refutes, harvests, PR comments or worker notes';
  - 'without the compromises made on the way';
  - 'It keeps one context for the whole raft';
  - 'so its context carries over'.
- Go through the rest in the same table: 'you start one by hand' (the ask's "manually start any cli"), 'Only a confirmed idea goes to z-design', 'with who made it' (Escalation's "who resolved", Design), and the Intent's 'then clears its context and takes the next raft'.
Lesson: z-design/spec-design-correspondence

### F3 [medium] E3b's landing-order claims were never run as merges: every in-section order conflicts, the c0261 line is one the draft changes, and the c0265 rule "the merge keeps its words, not the draft's" contradicts AC6's pins
Where: c0264.md E3b (the c0261, c0265 and c0260 bullets), Implementation steps 1, 2 and 5; mutants.sh `ok c0261-reworded`, `c0261-reworded-diagram`, `c0265-lost-line`; check.sh AC6 pins on the heartbeat sentences, `ROWS` (pinned order).
Evidence: the merge probes above.
- E3b: "c0261 first: ... step 1's three-way merge keeps that edit (the draft is unchanged there)". The draft changes that line (the c0117 relabel), so `git merge-file` reports 1 conflict there.
- "c0265 first: its `./zn lost` line in Order is kept by the merge (`c0265-lost-line` passes)": 1 or 2 conflicts.
- "c0260 first: its row stays": 1 conflict.
- The three `ok` variants are perl edits of the draft, not merges, so what they pass is one hand resolution that the design never states.
- The c0265 bullet also says "where c0265's PR changed the heartbeat sentences the merge keeps its words, not the draft's". But AC6 (sequestered) requires the draft's 'a heartbeat branch, not on `main`', 'A takeover deletes the old heartbeat branch' and 'a numbered copy of it continues the work'. Keeping c0265's words then fails AC6 on a README the design calls correct.
- The natural resolution of the Roadmap conflict (keep ours' c0265 row, add the draft's other rows below it) puts c0265 before c0260. `ROWS` pins the order, so AC7 fails ("roadmap issues differ") on a README with one true row per id.
Critique: z-design/quote-other-preps-before-promising asks, for each order, what turns red. The answer is recorded but not run, and the executor gets conflict markers with no rule for them. Step 1's "keep both sides' intent" does not say which side wins:
- on a pinned phrase;
- on a pinned label count (`LABELS` holds one `Order|c0265`, so a c0265 line with its own label beside the draft's "Lost work comes first ... *captured* (c0265)" fails AC7);
- on a pinned row order.
The three-way merge itself works (0 conflicts when nothing landed, and conflicts are flagged, not lost), so this is medium, not high.
Consequences: a stated resolution per conflict either keeps the sequestered pins (the draft's phrase wins) or says to escalate. The design has to pick one, and with F1 the c0265 orders become five layers.
Recommendation:
- Replace E3b's claims with the run results.
- Give step 1 one resolution rule per known conflict:
  - c0251 line: c0261's parenthetical plus the draft's `built (*exists* (c0117))`;
  - Order: fold a landed lost-work line into the draft's "Lost work comes first" bullet, one c0265 label;
  - Roadmap: the draft's row order, one row per id, state from the tracker.
- Add a general rule: where a landed PR's wording would remove an AC6 phrase, stop and escalate (zz-execute stop conditions), since check.sh cannot change in execution.
- Turn the `ok` variants into real merges in mutants.sh: ours = base with the landed hunk, `git merge-file`, the stated resolution applied, then `./zn check c0264`. Add one for the Roadmap order.
Lesson: zz-review/run-the-evidence-you-cite

### F4 [low] Step 1 names the issue folder by its prep path, which does not exist at execution, and E4's count is off
Where: Implementation step 1 (`z-nile/.tracker/issues/c0264/experiments/README.base.md`, `.../README.draft.md`); E4 ("Thirty-five mutants").
Evidence: z-ready moves the issue to `z-nile/.tracker/issues/active/c0264/` and rewrites only `check.sh` paths (z-ready step 3; `./zn find c0117` prints `z-nile/.tracker/issues/done/c0117`, the same layout). `grep -c '^run ' experiments/mutants.sh` gives 36, and `'^ok '` gives 4.
Critique: an executor running step 1 verbatim gets "No such file". It is easily recovered, but step 1 is the one command the design gives.
Consequences: none on the checks.
Recommendation: write the paths as `"$(./zn find c0264)/experiments/README.base.md"` (and the draft likewise), and correct the count to thirty-six mutants and four correct variants.

### F5 [low] `no_models()` is a blocklist of the ask's examples, so other model names pass
Where: check.sh `no_models` (`sonnet|opus|haiku|composer|xhigh|gpt|gemini|4\.[0-9]`); the c0261 Decided paragraph ("quotes no model names where it speaks of the models to use").
Evidence: `model-name-other` above ("grok-code-fast-1 or kimi-k2" in Models per command and activity): 10/10.
Critique: the decision is "no model names", not "not these names". The CLI names `grok`, `kimi` and `deepseek` must stay, so a word list cannot simply grow to cover them.
Consequences: a broader pattern must not match the six bare CLI names in The worker.
Recommendation: also fail on a CLI name followed by a model suffix (`(grok|kimi|deepseek|claude|gemini)-[a-z0-9]`) and on `fable`. Add `model-name-other` to mutants.sh (AC6).

## Lessons (candidate, for the lead)
- A design that labels another ticket's text re-reads the tracker for splits after every merge of main: a split moves outcomes to new ids that no label names. Check: for each id this text labels, does `origin/main` hold a ticket "split from" it, and which sentences does that ticket now carry? (F1)
- A landing-order claim about a merge is a merge that was run: ours = base with the landed hunk, then the real merge command, with its conflict count pasted, not an edit of the result. Check: is each "the merge keeps X" backed by a `git merge-file` run in the record? (F3)

Verdict: changes
