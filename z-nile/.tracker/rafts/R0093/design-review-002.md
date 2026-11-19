# Review 002: R0093 (raft mode)
Inputs: raft-f0417-chain at 00d730c81 (R0093.md, R0093/check.sh, harvest.md, design-review-001.md, design-refute-001.md); for c0248, c0300, c0256, c0247, c0260, c0262 and c0250: the document, check.sh, acceptance/ specs and experiments/ where present; f0417.md, d0331.md, done/d0333.md, c0394.md, c0252.md, c0253.md, c0321.md; z-nile/engine/stack.luau (`stack.order`), layergit.luau, readycheck.luau (`reason`), openlist.luau (`pending`, `problem`), dispatcher.luau:1897-1899, main.luau (`designOpen`, `cmd.finish`, the `^local ` lines), z-nile/templates/prompt.md; origin refs `R0093/*`, `proto-*`, PR #419, #305, #307 (after `./zn sync --fetch`, origin/main 134b0c2f0); the z-raft, z-design and zz-arch lessons. Probes, each through `./zn run`: `lune run` and `luau-lsp analyze` on scratch files of 199 to 210 top-level locals; `git grep -F` of every Theme quote. Not run: `./zn approve <id> --check` (denied in this session), so the Approvals bullet in Risks is unverified.
Grouped: [c0247@115948858213, c0248@522df34bcda5, c0250@9eea0c780136, c0256@2f28f8862449, c0260@134eb2ce6d76, c0262@4b0581349bb7, c0300@c0b2c6f77d89]

The Order parses (each id once, every in-raft `depends_on` points down; c0250 sits last against the id tie-break for a stated interface reason), the outside waits are as stated (c0263 active in R0099, draft PR #419; c0117, c0302, c0369 done; c0301 gone; d0331 prepared with no raft), `main.luau` has 201 lines starting `local `, the leftover branches `R0093/1/c0256` and `R0093/2/d0296` and PRs #305 and #307 are still open, and every string the Theme quotes is in the member it names. What fails is the raft as a whole: it groups members it knows cannot pass RC0 together, records the conflicts in a form no command reads (F1), restates six of them (F2 to F7), drops two that review 001 found (F8, F9), and misstates when and how the reds and the local cap will show (F11, F13).

### F1 [high] The O1 to O6 bullets are invisible to every command, so nothing holds R0093 for the owner's rulings
Where: R0093.md `## Open to the human` (lines 154-160), Risks line 143 ("This raft should not be readied until the owner rules O1"); z-nile/engine/openlist.luau:83-108 (`pending` matches only `^%- (F%d+):` and `^%- (JC%d+):`); readycheck.luau:175-260 (`reason`); main.luau:1559-1569 and 1674 (`designOpen`, the prepared gate); dispatcher.luau:1899.
Evidence: `openlist.pending` reads `- O1:` to `- O6:` as no bullet at all. `readycheck.reason`, which both `./zn ready` and `./zn work next` call, never reads the raft's open list; its only stops after design are the outside waits, the member contracts and approvals. The prepared gate (`designOpen`) asks only that each finding of the latest raft review that needs the human has a ruled `- F<n>:` bullet, and the O-bullets answer no finding (review 001's findings were all answered `fixed` in design-refute-001 for an older record). The dispatcher's `openHuman` is `openlist.pending` too. So once this review is answered, `./zn status R0093 prepared` passes, and the day R0099 lands c0263 (the raft's only outside wait), `./zn work next` takes R0093, readies it and starts building seven layers whose RC0 the document itself says is red. "Should not be readied" is prose that no step reads.
Critique: The tempting fix is to rename O1 to O6 as F1 to F6. That points the ids at this review's findings, which are not the same points, and a bullet that names no finding still gates nothing at `ready`.
Consequences: The open points must be findings of this review (F2 to F8 below are those points), answered in design-refute-002 as not fixed, each with a `- F<n>:` bullet and its options. The prepared gate then refuses until the owner rules each one, so the rafting PR either waits for the owner or lands without `prepared`. z-raft's own rule (§4) is the other way out: a finding whose fix needs a member's design takes that member out with `./zn unfold`. The owner's 2026-11-18 request does not rule on either.
Recommendation: In the raft document: delete the O-bullets. Answer F2 to F8 of this review in design-refute-002, and for each one you do not close by unfolding, write `- F<n>: <the conflict>. Answer: <yours>. Decision: <the options, from O1 (a) to (c) where they fit>` under `## Open to the human`. Run `./zn status R0093 prepared` and confirm it refuses with the unruled ids before you hand the PR to the owner. Keep O1's choice as the Decision of each bullet, so one ruling answers the set.
Lesson: z-raft/escalations-are-bullets, z-design/open-bullets-use-finding-ids
Erred: z-raft
Upstream: none

### F2 [high] c0260 rewrites c0247's plan-file sentence and overrides c0247's promoted AC2, but in one raft c0247's sequestered AC2 and AC8 run on the top layer, so RC0 fails
Where: R0093.md Whole-raft design, z-ticket (line 99) and O6 (line 160); c0260.md:187 (Overrides `tests/acceptance/c0247/docs.spec.luau :: AC2`); c0247/check.sh AC8 (`block_exact`) and acceptance/docs.spec.luau AC2.
Evidence: c0260's Overrides line names `tests/acceptance/c0247/...`, a path that exists only after c0247's own `done`; c0260's ruling "Just state the order" says c0260's raft waits for c0247's `done`. In R0093 nothing is promoted until the one `./zn done`, which runs `bash c0247/check.sh` (RC0) on a tree whose z-ticket paragraph c0260 rewrote.
Critique: The raft names the conflict and leaves it. It cannot be fixed in the raft document.
Consequences: Fixing it changes a sequestered contract of c0247 or c0260: a re-prep, a new approval, an unfold and a re-fold in two landings (z-raft/rafted-member-changes-stay-in-the-raft), and a new coherence review.
Recommendation: This needs a member's design to change. escalate to the user, with these options: (a) c0247 ships the final sentence that c0260's rulings "Reword c0247's plan-file sentence" and "Plan file keeps every restatement" ask for, and c0260 drops its Overrides line and its step that edits `tests/acceptance/c0247`; (b) c0247's AC2 and AC8 stop pinning the plan-file clause; (c) c0260 leaves the raft and is rafted after R0093 is done. Under (a) or (b), unfold the redesigned member(s) now (z-raft §4).
Lesson: z-raft/stacked-members-cannot-override-each-other
Erred: z-raft
Upstream: none

### F3 [high] c0250 retires the item answer path that c0256's sequestered specs and AC7 pin, and its Overrides target c0256 specs this raft never promotes
Where: R0093.md Whole-raft design, dispatch (line 86) and O4 (line 158); c0250.md:440-450 (Overrides: "c0256's promoted specs, as its redesigned raft promotes them before c0250", and "c0250 is a chore and changes all of them in its own raft"); c0250.md:273; c0256/check.sh:23; c0256/acceptance/retry.spec.luau:249, 272, 287.
Evidence: c0256's specs run `./zn dispatch retry c0010 --answer ...` on existing items, and its check.sh greps zz-rules for `**Questions and answers** (c0256).`. c0250 refuses `--answer` for an item, fails a step that leaves `questions.md` on an item, and plans to edit `z-nile/tests/acceptance/c0256/*`, which in R0093 do not exist; editing c0256's sequestered copies instead is a Sequestration high in code review. c0250's design says in so many words that it was designed for "its own raft".
Critique: As designed, the top layer either fails c0256's checks at `done` or keeps the item path and drops the user's "resolve carries it".
Consequences: c0250's prototype was built on the stopped c0256 build (7559481f); whichever member changes, c0250's E5 and E6 rerun on the c0256 that will ship.
Recommendation: This needs a member's design to change. escalate to the user: (a) c0250 leaves R0093 and lands after it, as designed; (b) c0256 is redesigned to answer only a capture (a `Scope decision` line on its "any step that stops with questions" outcome) and c0250 drops those Overrides; (c) c0250 keeps c0256's item path beside the block (against "resolve carries it"). The surviving design states item and capture behaviour in one place.
Lesson: z-raft/stacked-members-cannot-override-each-other
Erred: z-raft
Upstream: none

### F4 [high] c0262's sequestered work.spec builds `RaftFact.questions` and pins `questions.md` in its `blocked` action, both of which c0250 removes from the layer above it
Where: R0093.md Whole-raft design, work.luau (lines 88-91), O4; c0262/acceptance/work.spec.luau:27 (`questions = false`) and 85; c0250.md (`RaftFact.blocked` replaces `RaftFact.questions`).
Evidence: On the top layer `work.RaftFact` has no `questions` field, so the strictly typed literal in c0262's spec fails `./zn promote-check R0093` (RC0); its AC8 asserts the `blocked` action names `questions.md`, a signal `work.decide` no longer reads after c0250.
Critique: Either RC0 is red or a ticket that goes off course twice "blocks" its raft with a file nothing reads.
Consequences: Redesigning c0262 onto c0250's block puts c0250 below c0262 in the Order (legal: c0250 depends only on c0248 and c0256 inside the raft), and c0262's `blocked` then needs one of c0250's closed reasons.
Recommendation: This needs c0262's or c0250's design to change; escalate to the user which. If c0262: it blocks with `./zn block <R> <reason>` and `escalation.md`, its work.spec builds `RaftFact` without `questions`, and the Order moves c0250 to layer 5 or 6 below c0262.
Lesson: z-raft/stacked-members-cannot-override-each-other
Erred: z-raft
Upstream: none

### F5 [high] c0260's dispatched confirmation is a `questions.md` stop answered by `dispatch retry`, which c0250 fails on an item
Where: R0093.md O4; c0260.md:128 ("Keep headless, confirm later"); c0260/acceptance/skills-restated.spec.luau:25 (`has(d, "questions.md")`); c0250.md (an item's `questions.md` fails the chain; `retry` refused while blocked; Headless paragraphs rewritten to `./zn block`).
Evidence: On the top layer z-design's skill tells a dispatched step both to write `questions.md` (c0260, pinned) and to block (c0250). The first fails the chain with exit 1. c0260's pin is a bare substring, so every check passes while the flow is broken.
Critique: c0260's captured "Only a confirmed idea goes to z-design" has no working dispatched route on the shipped tree.
Consequences: The combined flow is block (`needs-decision`), the user's own `./zn idea <id> --confirm`, then `./zn resolve <id> retry`; resolve must not count as the confirmation.
Recommendation: This needs c0260's or c0250's design to change; escalate to the user which. The redesigned member pins that flow, not the word; if c0260 is redesigned onto c0250, c0250 moves below c0260 in the Order.
Lesson: z-raft/merged-text-read-against-captures
Erred: z-raft
Upstream: none

### F6 [high] The user ruled that c0248 goes back to design after d0331 lands, and c0248 is the base layer as designed before that ruling
Where: R0093.md Cross-raft waits (line 128), O2 (line 156), Why this order layer 1 (line 116); d0331.md:26; done/d0333.md:70.
Evidence: d0331: "Decided with the user (2026-11-14): "Any lowest layer". ... c0248 goes back to design after d0331 lands (its AC8 refusal and restack step change, its `baseFor` calls `mainFork` for the lowest unlanded layer, `depends_on` gains d0331)". c0248's `depends_on` is `[]` and its sequestered AC8 still pins the rule the user rejected. d0331 is prepared, raftless, and `./zn raft-plan` proposes `./zn new raft defect raft-order-names-non-members d0295 d0331`. Layers 6 and 7 build on c0248's `baseFor`, `done --through` and partial `stop`.
Critique: Building layer 1 builds a rule the user has already overruled, under everything above it.
Consequences: Once c0248 gains `depends_on: [d0331]`, `./zn ready R0093` refuses until d0331's own raft is done, so the whole raft waits for a defect raft that does not exist yet.
Recommendation: This needs c0248's design to change. escalate to the user, with O2's options, as a `- F6:` bullet; under (a) say in Cross-raft waits that R0093 then waits for d0331's raft and c0248's re-prep.
Lesson: z-raft/fold-reads-what-other-rafts-say-of-the-member
Erred: z-raft
Upstream: none

### F7 [high] Grouping c0248, c0262 and c0250 here contradicts "Keep one raft" (R-vision) and c0262's "rafted after R-vision lands", and c0248's AC14 pins a README sentence this raft makes false
Where: R0093.md Theme lines 40-42, O3 (line 157); c0248/acceptance/docs.spec.luau:190 (`"c0248 to c0254 are one raft (R-vision), delivered as a stacked PR set in that order:"`); c0262.md:127 ("c0262 must not be rafted with c0248"); c0286.md:237 (the ties ruling recorded as "GUESS made by Claude, NOT YET CONFIRMED by the user").
Evidence: R0093 lands c0248 and c0250 without c0249 or c0251 to c0254, so the sentence c0248 pins is false on the day it lands. The only record that dissolves R-vision is c0286's unconfirmed guess; neither the 2026-11-15 words nor the 2026-11-18 request name R-vision.
Critique: z-raft may not settle two of the user's rulings against each other.
Consequences: If the user dissolves R-vision, c0248 (AC14, its Idea, the README Roadmap text) and c0250 (its "third layer") are re-prepped and c0262's line is updated; if not, c0248, c0250 and c0262 leave R0093.
Recommendation: This needs member designs to change either way. escalate to the user, quoting c0248 Q8 and c0250 Q7 "Keep one raft", c0262's "Accept both (Recommended)", and c0286's unconfirmed guess, as one `- F7:` bullet.
Lesson: z-raft/fold-reads-what-other-rafts-say-of-the-member
Erred: z-raft
Upstream: none

### F8 [high] c0262's limited view leaves out c0260's confirmed idea, and this document dropped the conflict review 001 F8 found
Where: R0093.md Whole-raft design (no `finalview` entry; c0260 and c0262 share no Touched path, so the module list cannot surface it); c0262.md:89, 98 (`finalview.ask` reads `## Ask (verbatim)`, `## Interview`, `## Idea`, `## Confirmation`); c0260.md:136 ("no `## Idea` section exists (the clean idea is the Problem, Solution and Non-goals)"); c0262/acceptance/view.spec.luau:125-139.
Evidence: c0262 says it was designed while "c0260 is under re-prep ... this design reads the sections by name only". c0260's current record has no `## Idea`, and view.spec asserts the base's Problem is not in the ask when those sections are present. So for every ticket captured with c0260's record, layer 6's reviewer judges the diff without the idea the Confirmation line confirms, and every check is green. c0260 makes `capturecheck.section` the one fence-aware reader; c0262 reads the same sections with its own.
Critique: The interface is a data shape (an issue document's sections), not a module, so the Whole-raft design's module walk misses it; review 001 named it and the regrouping lost it.
Consequences: The fix contradicts view.spec and AC1's wording, so it is a contract change of c0262; the ten hand-made records with `## Idea` must still read as today.
Recommendation: This needs c0262's design to change: `finalview.ask` reads through `capturecheck.section` and, for a record with `## Confirmation` and no `## Idea`, adds the base's Problem, Solution and Non-goals; view.spec gains a c0260-shaped case and a fenced-heading case. Add a Whole-raft design entry for the record shape (c0260 writes, c0262 reads), and escalate with F1's bullet if c0262 stays.
Lesson: z-raft/interface-names-every-writer
Erred: z-raft
Upstream: none

### F9 [medium] c0262 assumes rafts in flight carry `layers: reviewed` and tells a worker to run `done --through`, which c0248 refuses on every unmarked raft, R0093 included; this too was dropped
Where: R0093.md Risks "c0248 cut-over" (line 146); c0262.md:112 (`work.finalStep`: "land the green layers first with `./zn done <R> --through <the issue below>`") and 127 ("the rafts that will actually be in flight when c0262 lands are those readied after c0248 landed, which carry `layers: reviewed`").
Evidence: c0248 and c0262 land in R0093's one bind, so every raft in flight then was readied by an engine without c0248 and is unmarked; c0248 outcome 9 refuses `--through` for them, and the Risks bullet says so for R0093 itself.
Critique: At the moment a ticket blocks, the worker is told a command that will be refused, in every raft in flight after the bind.
Consequences: Gating the hint needs a marker fact in `RaftFact`/`workread`, defaulting so that work.spec's existing case still holds.
Recommendation: This needs c0262's design to change (state and pin the unmarked case: no `--through` hint, or "the raft lands whole"). Say so beside the Risks bullet, or escalate with F1's bullet.
Erred: z-raft
Upstream: none

### F10 [medium] O5 is fixable in the raft document, but the document says it needs a member's design change
Where: R0093.md Whole-raft design, dispatch (line 86), O5 (line 159); c0256.md item 7 (the parent exchange in any nested step's prompt); c0262.md (the ticket reviewer is told only `README.md`).
Evidence: c0256's nested cases use `--mode design` (c0256/acceptance/step.spec.luau:242, 256), so an exception for `zz-review <issue-id> --mode final` changes no sequestered case of either member. c0262's dispatch.spec runs without a parent, so it stays green too. Review 001 F10 recommended exactly this in the raft document.
Critique: Escalating a point the raft can settle adds a ruling the owner should not have to make.
Consequences: c0262's layer then owns a tooling-spec case (not sequestered) that runs the final review nested under a fake parent with an exchange and asserts the prompt names no path outside the view.
Recommendation: In the raft document alone: in the Whole-raft design, dispatch entry, write "a ticket's final review (`zz-review <issue-id> --mode final`) gets none of c0256's exchange paragraphs, its own or its parent's; layer 6 adds the exception to `dispatch.prompt` and the tooling case above", and drop O5.
Erred: z-raft
Upstream: none

### F11 [medium] With this Order every known conflict passes at its own layer's finish and first fails at `./zn done`, after all seven layers; O1 (c) tells the owner the executor stops "at the first red member check"
Where: R0093.md O1 (c) (line 155), Risks line 143, Why this order layers 6-7 (lines 121-122); main.luau:4042 (`cmd.finish` runs `runCheck(issue)`, the finishing issue's check only); zz-execute step 2 ("this layer, the layer below, and this ticket's checks").
Evidence: c0260 (layer 5) passes its own check while c0247's AC2 and AC8 go red; c0250 (layer 7) passes its own while c0256's and c0262's go red. Placing c0250 last, against the id tie-break, is what makes each layer below it green at its own finish. No finish runs a lower member's check, so the first red is RC0 in Phase 3, after about 8,000 lines.
Critique: The owner is asked to choose (c) on a cost that is not the real one.
Consequences: If any member stays as designed, the executor needs a rule that shows the red at the layer that causes it.
Recommendation: In the raft document alone: rewrite O1 (c)'s cost ("the first red is RC0 at `./zn done`, after all seven layers"), and add to the Whole-raft design (which the prompt carries) that before each `./zn finish` from layer 2 up, the executor runs `./zn check <id>` for every member below and stops on a red one as an interface conflict.
Lesson: z-raft/cross-raft-wait-bites-at-the-first-red-layer
Erred: z-raft
Upstream: none

### F12 [medium] The Experiments phase cannot be run as written, comes too late, and like Risks' step 0 is not in the prompt
Where: R0093.md Experiments phase (line 133), Risks step 0 (line 144); c0300.md:109 (E7: "c0248's `experiments/prototype.patch` no longer applies to today's `main`"); done/d0333.md:70; c0250/experiments/prototype.patch header (base includes `R0093/1/c0256` 7559481f); c0262 has no `experiments/` folder and `proto-c0262` (b4eac25e) is a local branch only (`git ls-remote origin` has none); z-nile/templates/prompt.md (carries THEME, ORDER, INTERFACES, WORKSTREAMS, ARCHITECTURE, not Risks or Experiments).
Evidence: The first patch in the Order fails to apply to origin/main, c0250's patch is built on a c0256 that will not ship, and c0262's prototype is not reachable from another machine or a dispatched step. The run is placed "before `./zn start`, or as Phase 1", after `ready`, but it is the evidence F2 to F8's rulings need before `ready`.
Critique: The executor meets three unapplicable patches with no instruction, and a red found in Phase 1 means `./zn stop` and a re-prep, not a build step.
Consequences: Someone must rebase c0248's patch on today's main (d0333's 3-way hunk), rebuild c0250's on the shipping c0256 (or on c0256's patch), and push `proto-c0262`; each is prep work in a member folder.
Recommendation: In the raft document: make the combined run a step before `ready` owned by the rafting lead (or by each re-prep under F1's option (a)), name who refreshes each stale patch, record the result in the raft document, and move step 0 and this run into a section the prompt carries (the Whole-raft design) with "with the user's yes" kept.
Lesson: z-raft/run-sequestered-specs-on-all-prototypes-together, z-raft/member-handshakes-reach-the-order
Erred: z-raft
Upstream: none

### F13 [medium] The local-cap facts are false: `luau-lsp analyze` does not catch the limit, and the `^local ` line count is not the measure
Where: R0093.md Whole-raft design, main.luau (line 51: "`luau-lsp analyze` (the gate's types stage, RC0) fails the file past it"), Exit criteria line 137 ("its types stage is the `main.luau` local cap"), Risks line 145, Experiments phase ("counts `main.luau`'s locals").
Evidence: Probes through `./zn run`: a file of 201 top-level `local vN = os.clock()` makes `lune run` fail ("Out of local registers when trying to allocate v201: exceeded limit 200") while `luau-lsp analyze` on it exits 0 with only LocalUnused warnings; 210 locals of constant literals run fine (constants fold away). Today's main.luau has 201 lines starting `local `, two of them (8736, 8737) declaring two names each, and it compiles: the line count overstates the registers in use, so the document's "201 against a limit of 200" is not the headroom.
Critique: An executor watching the types stage for the failure will not see it there; it shows as every `./zn` command failing to start. A line count will not say which layer crossed the line.
Consequences: The measure is compiling main.luau on each layer, which any `./zn` command does.
Recommendation: In the raft document alone: replace both sentences with "the limit is Luau's 200 local registers, which `lune run` reports when `./zn` starts (luau-lsp does not); each layer runs `./zn --help` after its last main.luau edit, and the first that fails moves helpers into one table", and change the Experiments phase from "counts locals" to "starts `./zn` on the merged tree".
Lesson: zz-arch/main-luau-local-limit
Erred: z-raft
Upstream: none

### F14 [low] The Theme misstates what changed and where its rulings come from, and again leaves out decisions the members rely on
Where: R0093.md Theme lines 33-43.
Evidence: (1) "c0248, c0260 and c0262 carry the same design as that review read, only `designed-by:` added": c0260 has no `designed-by:` and is unchanged (its recorded hash 134eb2ce6d76 is the one review 001 read). (2) "c0250 was re-prepared ... two sequestered lines": since e0496e5e6 its block-resolve.spec gained 56 lines and lost 15, and work-board.spec gained 4 and lost 1 (`git diff --numstat`). (3) "the two 2026-11-15 rulings are quoted from this raft's own design-refute-001.md": neither quote is in design-refute-001.md; they come from this document's history (979dc94ae, #428). (4) The Theme leaves out c0256's "Capture, then depend" and "Stop and redesign", c0260's "Plan file keeps every restatement" and "Only tickets created after c0260 lands", and c0262's "Before each layer completes" and Scope decision "We should start using fable for final raft review and for the idea phase" (each found by `git grep -F` in its member); design-refute-001 F14 says c0256's two were added.
Recommendation: In the raft document alone: correct (1) to (3) and copy the missing lines in.
Lesson: z-raft/theme-quotes-are-copied, z-raft/copied-raft-text-is-reverified
Erred: z-raft
Upstream: none

### F15 [low] The Theme quotes f0417 as not redesigning the members, but f0417 changes c0260's cap and says the owner asks for 5
Where: R0093.md Theme line 18; f0417.md:19, 34, 38.
Evidence: f0417: "c0260's unbuilt design caps the idea loop at 3 challenges where the owner asks for 5" and "c0260's cap of 3 is changed to 5"; it also gives c0250's `review-exhausted` reason a new trigger. The raft builds c0260's three-challenge cap (Theme line 25).
Recommendation: In the raft document alone: quote those f0417 lines beside the Non-goals sentence, and add the cap to the decision F2's or F5's ruling asks (a c0260 re-prep can take 5 if the owner says so, or 3 ships and f0417 changes it).
Erred: z-raft
Upstream: none

### F16 [low] The raft does not name the prepared chores whose wait it lengthens
Where: R0093.md Cross-raft waits (lines 124-130).
Evidence: c0394 "Findings stay in their raft" (prepared, raftless) depends only on c0248 and the done c0369; c0252 depends on c0248 and c0250, c0253 on c0248, c0250 and c0260, c0321 on c0250. Each now waits for R0093's one `done` of about 8,000 lines rather than for its own dependency; `./zn raft-plan` proposes c0394 as a raft of its own.
Recommendation: In the raft document alone: list them under Cross-raft waits as items waiting on this raft, and say whether c0394, the only one with nothing else outstanding, should join (a fold is a new record and a new review).
Lesson: z-raft/grouping-cost-checks-every-wait
Erred: z-raft
Upstream: none

Verdict: changes
