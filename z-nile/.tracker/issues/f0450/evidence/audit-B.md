# Audit B: closing f0422, f0423, f0425, f0437 properly

Read-only audit of origin/main = main = `3e7b197e3` (2026-11-24). Nothing was written in the repository. Commands run: `./zn capture`, `./zn guesses`, `./zn rounds --kind design|code`, `./zn approve <id> --check`, `./zn status <id>`, `./zn audit` (0 errors, 0 warnings), `./zn busy` (bounded), git log/show, gh pr view, grep/read.

## Findings that apply to all four

- **No raft and no lifecycle.** All four tickets are `status: new`, `design: draft`, `raft:` empty, no approval (`./zn approve <id> --check` says "has no approval" for each), and no `harvest.md`. `./zn done` takes only a raft id, so today it cannot run for any of them. The first refusal on the path is `./zn ready`: design not ready, raftless issue, and for f0422, f0423 and f0425 a `check.sh` with no `check` line at all (each has only the template comment at `check.sh:12`).
- **There are no acceptance specs to promote.** No ticket has an `acceptance/` folder. Every spec the hand-built slices wrote is already in `z-nile/tests/tooling/` (plus Go tests and node tests run through tooling specs), and the gate already runs them. "Not promoted into the gate" is not the real gap. The real gaps are: (a) three of the four `check.sh` files name no spec, and (b) nothing binds those specs to the tickets' acceptance criteria. `trace.luau:883-907` (`isSpecForIssue`) accepts any spec under the home's `tests/` as a ticket's own spec, so tooling specs can fill the trace's test column once `./zn finish` records them green in `results.txt`.
- **The trace cannot link claims to code that is already merged.** A closing raft's layers would change no source file, because the code is on main. `trace.luau:1149-1155` then requires the code cell to be `none` on every row, and refuses any other value. So `./zn trace --check` would pass while proving nothing about the code. The final review would have to judge every claim against main's code by reading it, outside the trace's mechanical check. This is a gap in the tooling for any after-the-fact close. The person decides whether to accept "code: none plus the reviewer's reading", or to change the trace first. (Memory rule: a finding does not become a ticket without the person.)
- **Splitting follows z-design's rule** (`z-nile/skills/z-design/SKILL.md:10`). A split moves outcomes into new issues captured through z-idea. That is the owner's call, recorded as `Scope decision (user, YYYY-MM-DD): "<words>"` naming the new ids. For the trace, every claim from the capture that moves out needs its design cell set to `not met: "<ruling>"`, quoting a `Ruled (user, …)` bullet under `## Open to the human` (zz-review Final mode, step 1). A bullet that is only partly delivered (f0423 S1 and S2, f0437 S2) cannot be half "not met". Its row cites the delivered part, and the Scope decision line has to say exactly which half moved.
- **Guesses are append-only** (zz-rules `guess` row: "A pushed guess is never changed or removed"). Guesses about unbuilt work stay in the closing ticket's `guesses.md`, and the owner approves them along with it. The new ticket can only re-record them.
- **Path:** f0422, f0423 and f0437 need the full path: z-design claim, design review rounds, `design: ready`, prep PR, `./zn approve` by the owner, then z-raft, `ready`, one layer each, code review, trace and final review, then `done`. None of them qualifies for the light path: each has `Overrides:` entries or real size, and the light path needs `risk: easy` and `Overrides: none` (zz-rules `ready` row). f0425 is the one candidate for the light path (see below). One raft holding f0422, then f0423, then f0437 fits z-raft's policy (all features, all z-nile, shared surface, f0437 builds on both) and needs one coherence review. Each layer's diff would be documents only (the Verification log). A per-layer code review of a documents-only diff adds little; the final review carries the weight.

---

## f0422: Tributaries and banded board

Merged: `17cccfbc8` (#686, slice 1: Flow and bands), `48bf82b5a` (#691, slice 2: tributaries, in-flight band, dependency info), `05dc1960c` (#696, chip contrast). No review files exist for any of them; each PR has only the publish comment. Capture: `70c1aa095` (no marker).

### 1. Outcomes
| outcome | state | code on main | proof (spec, in gate?) |
|---|---|---|---|
| P1 grouping by theme, how much is done | delivered | `z-nile/engine/tributaries.luau:38` (parse), `:211` (counts); `board.html:328-337` (chips) | `tests/tooling/board-flow.spec.luau` "the model gives each unit its tributary and each tributary four counts" (gate) |
| P2 what can be worked now, and how far the rest is | delivered | `depgraph.luau:52` (bands); `board.html:202-226, 341-346` | `depgraph.spec.luau` "a chain has one band per step", "a diamond…"; `board-flow.spec` "Flow splits band 0 into In flight and Workable now…" (gate) |
| P3 draw a raft's dependency links | partly: text chips and a pane only (`board.html:261-276, 469-472`), no drawing | | |
| P4 a worker on one theme | delivered **by f0420** (#758), not by this ticket | `work.luau:1019-1040, 1724-1728` | `work-tributary.spec`, `work-theme-cli.spec` (f0420's, gate) |
| S1 named group, one-line purpose, "one editable ordered list whose entries are rafts and raftless tickets" | partly / changed: `<root>/tributaries.toml` holds the ordered definitions; membership is a `tributary:` line on each unit (the lead's guess, `f0422.md:26`), not a list. **Changes a captured outcome: needs the owner's Scope decision, not a guess** | `tributaries.luau:38`; templates `z-nile/templates/{issue,raft}/doc.md` | `tributaries.spec` "parse reads the ordered definitions…" |
| S2 a raft's ticket belongs to its raft's tributary and is never listed itself; a done unit stays | changed after it was built: f0437 G24 makes a raft count in its own theme **and in every theme its members name** (`tributaries.luau:180` themesOf; `board.luau:1350` override comment). Contradicts S2's wording: needs a Scope decision | | `tributaries.spec` "a unit's tributary is its own line…" and the G24 case "four views name the same units" |
| S3 gate fails for a unit in no tributary or in two | changed by the same guess: `audit` errors on a line that names an undefined tributary; a unit with no line is `unsorted`, not an error. Needs a Scope decision | `audit.luau:588-596` | `tributaries.spec` "audit.tributaries fails a bad tributary…" (gate, also run on the real tree) |
| S4 `./zn list <tributary>` | delivered (with G24's raft rule) | `main.luau:3327-3366` | `tributaries.spec` "list takes a tributary and a state in either order…" |
| S5 four counts per tributary, including "waiting for the owner's approval" | partly: the board's third count is **not approval**. `board.luau:1230-1344` asks `classify` with `approval = false`, so it counts only units with `questions.md`, while the chip tooltip (`board.html:333`) and the zz-rules board row say "waiting for approval". The real approval count exists only in the app's Themes view (f0437 step 5, `themefacts.luau`) | | board-flow "…four counts" |
| S6 bands top to bottom: waiting for approval, workable now, band N | partly: the top section is "In flight" (`board.html:217-219, 343`); there is no approval band | | board-flow "Flow splits band 0…"; promoted `c0118/page.spec.luau` |
| S7 band N = 1 + highest band waited on | delivered | `depgraph.luau:52` | `depgraph.spec` "a unit waiting on bands 0 and 2 is in band 3" |
| S8 a raftless ticket is placed by the same rule | delivered | `depgraph.luau:155` (units) | depgraph and board-flow cases |
| S9 unblocks count (direct and indirect), card shows it and what it waits on, workable band sorted by it | delivered | `depgraph.luau:95, 120`; `board.html:261-270` | `depgraph.spec` "unblocks counts every distinct unit downstream, once", "order puts the most unblocking first…" |
| S10 selecting a card highlights everything upstream and downstream | **not built** (no highlight code in `board.html`) | | |
| S11 focused one-raft graph with a line per dependency | **not built** | | |
| S12 `./zn work <tributary>` gives only that tributary's units, stops when none is workable | delivered **by f0420**, with different meaning: "limited to its units **and the units they depend on**" (`main.luau:140` usage, `work.luau:1019`). Needs a ruling | | f0420's specs |
| D1 (Decided 2026-11-20) workers panel: one row per live worker, CLI, capabilities, activity or idle, last heard; a card names its worker; "waiting for a worker with <what it needs>" | partly, **by f0424** (#715): `board.html:280-322` (strip with CLI, `can` in the tooltip, activity or idle, last heard; card chip names the CLI). **Not built:** the "waiting for a worker with …" mark | | board-flow "every string from the daemon is escaped", "a snapshot with no workers says so…" (f0424's cases) |

### 2. Document compared with what was built
- `## Design` (`f0422.md:48-62`) is the empty template. Touched modules, Affected specs, Unknowns, Test plan, Rules and mutants, Acceptance criteria and Implementation steps are all empty. Only the Regression guard (`:70`) was written. It names the promoted specs the slices changed (c0042 model and smoke, c0107 views, c0118 model, page and docs, and c0118/page again for slice 2) but **no chore**. z-design step 3 (override check) requires a chore in `depends_on` for a non-chore, so a design reviewer will raise a high finding. The owner has to rule on it.
- Acceptance criteria: none. Check lines: none. Specs that would back them already exist (above).
- Reviews: idea-review-001 (`revise`), answered in idea-refute-001 (F1-F3 revised, F4 disputed). Design rounds: "no review yet; run design review round 1 of at most 5". Code rounds: none.
- Open to the human (`f0422.md:100`), verbatim and short: "F4: The solution isn't the smallest… highlighting upstream and downstream…, the focused one-raft graph…, or the text graph… Answer: disputed…". **Unruled.** z-design step 1 refuses the claim (`status preparing`) until it is ruled.
- Guesses: `./zn guesses f0422` gives 0 (there is no guesses.md). The inline "Guess (lead, 2026-11-20)" at `:26` is not recorded, and it rewrites S1 and S3, which is scope.
- The "later slice of this ticket" wording in D1 (`:24`) is stale: f0424 built the strip.

### 3. Smallest honest split
- **Close now as f0422:** P1, P2, S4, S7, S8, S9. Also S1, S2 and S3 once the owner rules (a Scope decision accepting a `tributary:` line per unit, no failure for a missing line, and G24's raft rule). Also S12 and P4, ruled "delivered by f0420 (#758), including the units the theme depends on". Also S5's done, in-flight and not-started counts.
- **New ticket, working title "Board: the approval band, dependency highlight and graph, and waiting for a worker":** S6's approval band; S5's approval count on the board (or the owner rules "the board's count is 'waiting for you'; the approval count is the app's Themes view", which needs only a relabel); S10; S11; P3; D1's "waiting for a worker with <what it needs>" mark.
- Clean except S5: its four counts are one outcome and one column is wrong. Either the owner moves that column, or the chip is relabelled (a one-line source fix in `board.html:333` and the zz-rules board row; a layer that changes source is fine).

### 4. What blocks closing today, and the work
Blocks today: the claim is refused because F4 is unruled. After that: no design, no ACs, an empty check.sh, no design review, no approval, no raft. Work:
1. Owner rulings: F4; Scope decisions for S1, S2 and S3 (the line-per-unit model, G24), S12 and P4 (f0420), S5, and the split naming the new id; Overrides without a chore.
2. Write the Design as built (depgraph, board model and Flow page, tributaries, audit, `list`, templates and skills), Touched modules, Affected specs, Rules and mutants from the existing spec cases, about 9 Checked ACs, and about 9 `check` lines naming `depgraph.spec`, `board-flow.spec`, `tributaries.spec`, and promoted `c0118/page.spec`, `c0042/*`, `c0107/views`. Record the lead's guess with `./zn guess` or replace it with the Scope decision.
3. Design review (round 1 of at most 5), refute, harvest, `design: ready`, prep PR, owner approve, then the raft (shared with f0423 and f0437, see above).

### 5. Estimate and risks
About 220 lines (Design about 90, rules about 20 rows, ACs and test plan about 20, check.sh about 10, decisions about 10, refute and harvest about 20 per round). Rounds: design 1 to 2, raft coherence 1 (shared), code 1, final 1 to 2 (shared). Risks:
- Pinning the Flow order with "In flight" first, in check lines that cite `c0118/page.spec`, conflicts with S6's approval band if the owner keeps it in the remainder. The remainder would override a promoted spec a third time.
- S12 and D1 cite code from f0420 and f0424, which are also `new`. They need the same treatment.

---

## f0423: Approval session

Merged: `57405bfa1` (#688, the design, merged with no design review), `bf45c7543` (#697, step 1: walk one raft), `fe7230e0d` (#699, scope line: mockups). Capture `70c1aa095`.

### 1. Outcomes
| outcome | state | code | proof |
|---|---|---|---|
| S1 `./zn approve <tributary \| raft \| ticket>` lists what waits and starts the CLI walkthrough | partly: raft, `--walk <ticket>` and no scope are built; **tributary is refused** (`approvewalk.luau:1138`: "tributaries come with the board's reader") | `approvewalk.luau`, `approverun.luau`, `waiting.luau:23,47,63`, `boundcmd.luau:454-513`, `agentenv.luau`, skill `z-approve` | `tests/tooling/approve-walk.spec`, `approverun.spec`, `waiting.spec`, `approve-hook.spec` (gate) = AC1-AC7 |
| S2a the walkthrough records each approval with the existing hash | delivered (`--apply`, y/N on /dev/tty, hash still equal, `who … (walkthrough <run>)`) | `approvewalk.luau` | approve-walk.spec (AC5) |
| S2b no raft with an unapproved guess enters its final gating review | **not built**: `work.luau:68` reads `unapproved` "once the final review is approved"; the wait is still after the final review (AC8, AC9) | | |
| S3 a dependent raft starts from the prerequisite's layer branch; from its prep branch at idea or design | partly, through f0420 and the readiness rules (`ready --on <R-id>`, `Lands: approved`; zz-rules `ready` row); the prep-branch base is **not built** (`f0423.md:113` "Guess (prep): f0420's design takes it") | | |
| S4 a chain of approved rafts lands bottom-up | f0420's (seam); f0423 §8's printed "approved; ./zn work R0060 …" line is **not built** | | |
| S5 send back to the guess's stage, requeue, restack, one lesson per changed guess | **not built**: no `rework.luau`, no `./zn rework`; `--apply` prints "Nothing changes yet: ./zn rework is not built" (refute-001 F7) | | |
| D1 (Decided 2026-11-21) a UI ticket gets a clickable mockup: design makes it, the design review judges against it, the walkthrough opens it, the final review compares | **not built**: no skill under `z-nile/skills/` mentions a mockup; f0425's mockup was made by hand | | |

### 2. Document compared with what was built
- Design sections §1-§5 (`f0423.md:39-84`) match step 1. §6 (rework, `:85-103`), §7 (lessons, `:104-109`) and §8 (the wait, `:110-111`) describe unbuilt steps 2 to 5. Stale lines: §1 says f0422's board count calls `waiting.unit` (`:41, :49, :115`), which it does not (`board.luau:1330`, `approval = false`); §7 names skill `z-ticket` (`:105`), since renamed to z-idea (c0436).
- **Contract hazard:** the fence at `:87-94` holds a line `## W1 (design, …)` (`:89`). `contract.luau` `bodyOf` ends the Design section at any line starting with `## `, so `:89-133` (end of §6, §7, §8, Seams, Scalability, Maintainability, Usability, Touched modules, Affected specs) are neither hashed nor approved. f0437's own open question 3 (`f0437.md:659`) counts 43 such lines for f0423.
- ACs AC1-AC16, JC1 and OC1 (`:162-182`): **none has a check line** (`check.sh` holds only the template). Specs exist for AC1-AC7 and part of AC14. The specs the Test plan names for AC8-AC16 (`gate`, `rework`, `lessons`, `docs`, `tributary`, `idea` .spec.luau, `:151`) do not exist.
- Reviews: idea-review-001 (`revise`), answered "revised". **No design review was ever filed** (PR #688 merged without one; `./zn rounds f0423 --kind design`: round 1 due). Code: `refute-001.md` (F1-F13) and `refute-002.md` (F6, N1-N4) answer code reviews 001 and 002, **whose review files were never committed** (`git log --all` holds no `review-*.md` under f0423). `./zn rounds --kind code` sees none, and these refute files sit in the issue's folder, while zz-rules puts refutes in the raft's folder.
- Open to the human: "none". Guesses: 0 recorded; the inline "Guess (prep)" at `:113` is not in a guesses.md.
- Overrides (`:143`): f0423 changed promoted `c0115/layout`, `c0117/dispatch` and `f0399/land` itself ("no separate chore"), against z-design's rule for a feature. It needs an owner ruling.

### 3. Smallest honest split
- **Close now as f0423 ("Walk a raft's approvals"):** step 1 = AC1-AC7, JC1, the built part of AC14 (z-approve exists and is linked; zz-rules, AGENTS.md and the usage text list the forms); S1 for raft, ticket and no scope; S2a; P1 without tributary.
- **New ticket, "Approval session, steps 2 to 5: wait before the final review, rework and lessons, tributary scope, mockups":** S1's tributary scope (AC15); S2b (AC8, AC9); S3's prep-branch base; S4's line; S5 (AC10-AC13, AC16); the rest of AC14 (search `ruled` lessons before a guess, "an assumption is a guess"); D1 (the mockup rule in z-design, zz-review and z-approve); OC1's change half; the Overrides of `f0399/pick`.
- Clean at the level of ACs and implementation steps (the design already cuts at step 1). S1 and S2 are split bullets (see the general findings). Moving §6-§8 out also removes the fenced `## W1` from f0423's contract. The new ticket must rewrite that fence (indent the sample) or inherit the hazard.

### 4. What blocks closing today, and the work
Blocks today: no design review, no check lines, no approval, no raft. Work: owner Scope decision for the split and the new capture; move §6-§8, AC8-AC16, steps 2-5 and OC1's second half; fix the stale §1 and §7 lines; 7 to 8 `check` lines (`waiting.spec`, `approverun.spec`, `approve-walk.spec`, `approve-hook.spec`, plus a docs check for AC14's built part); record the Seams guess; owner ruling on the chore-less Overrides; design review from round 1, refute, harvest, `design: ready`, prep PR, approve, raft layer.

### 5. Estimate and risks
About 290 lines (f0423 doc about -110/+40, check.sh +8, the new ticket's capture about 130 lines of moved design, refute and harvest about 20 per round). Rounds: design 1 to 2 (the first ever), code 1, final 1 to 2. Risks:
- The two code-review rounds are known only from their refutes, so `./zn lessons --uncovered` passes vacuously and their findings were never harvested.
- If the owner answers f0437's question 3 with a fence-aware `bodyOf`, f0423's hash changes and its approval has to be given again.

---

## f0425: App approvals view (the mockup)

Merged: `07495f654` (#700), `e18eeaeb9` (#716), `5184cbeb7` (#718), `aa88f9cc2` (#719), `0b1653326` (#723). Capture `480f79419`: Problem is one line; Solution is the template, so the trace gets P1 and no S claims.

### 1. Outcomes
| outcome | state | where | proof |
|---|---|---|---|
| P1 an app view for approvals: the queue, each ticket explained, each guess with its options, approve or send back | delivered **as a mockup on simulated data**: `z-nile/.tracker/issues/f0425/mockup/index.html` (2,805 lines). The view on real data is f0437 step 4a (#755, #772). Needs a Scope decision "f0425 is the mockup" | | no spec checks the mockup's content; `tests/tooling/app-copy.spec.luau` (gate) only checks that `z-nile/app/index.html` equals it plus two edits |
| D1 (2026-11-21) Workers and Stats views; the app is built on from the mockup; "really vibrant stats … updates every time a step forward is recorded" | delivered in the mockup (simulated); the live Stats view is not built (f0437's remainder) | #716 | |
| D2 send-back with a stage and a required instruction; every item routable and openable in an AI CLI (`zn talk`); Tickets and Rafts modelled | delivered in the mockup ("Send back" ×8, "Talk" ×64, Tickets and Rafts views); real talk is f0432's | #719 | |
| D3 philip-bergen.com colours and fonts in the mockup and README.html; purple replaced | delivered | #723 | no contrast check in a spec |
| D4 seven stages, "bundle" | delivered in the mockup ("bundle" ×27); the noun stays open (c0436) | | |

### 2. Document compared with what was built
- Solution, Non-goals and Design are empty templates (`f0425.md:29-47`). No AC, no check line, no review, 0 guesses, no `## Open to the human` section.
- **`idea: unchallenged`** (`:12`). z-design step 1 refuses the claim until `./zn idea f0425` has run. That command is the only writer of Problem, Solution and Non-goals.

### 3. Split
The whole of f0425 can close as the mockup, with no new ticket. The live views belong to f0437 and its remainder, and the talk control to f0432. One owner Scope decision: "f0425 delivers the clickable mockup; the real view is f0437's".

### 4. What blocks closing today, and the work
Blocks today: idea unchallenged, no design, no check line, no approval. Work: `./zn idea f0425` (check that it keeps the four Decided lines); `risk: easy` with a `### Short note`; one AC; one `check` line, either an existing spec or a small new mockup-content spec (views, send-back requires a message, Talk on items, stages; about 60 lines). Then `./zn ready f0425` (light path: the single light raft in the claim commit) and the final review only (at most 2 rounds for easy).

### 5. Estimate and risks
About 90 lines (idea about 20, note and AC about 10, check.sh 1, optional spec about 60). Rounds: idea 1 to 3, final 1 to 2. Risks:
- "Test red first" cannot be honoured after the fact. Record it as a guess.
- The final reviewer may write `Level: normal` (2,805 lines, coupled to the app through app-copy), which sends it down the full path.
- `./zn idea` rewrites the Problem, so the Decided lines must survive it.

---

## f0437: The app on the live daemon

Merged: `a479173b2` (#732, step 1: serve the app, Workers live), `13f2c3f4e` (#755, step 4a: Approvals), `dfd07dbc5` (#760, empty lists defect), `aae259463` (#763, step 5: Themes home view and strip), `6364bc777` (#772, step 6 slice 1: markdown, whole sections), `c5b6341dd` (#788, step 6 slice 2: units index, id links, detail view). Capture `621fa1a9f` is one line ("The app: the live daemon serves the views with real data and embedded terminals"), so the trace gets P1 only, and "embedded terminals" is not built. The outcomes from the idea stage are on main since `8634ba77e` (#725), which is what scope is judged against.

### 1. Outcomes
| outcome | state | code | proof |
|---|---|---|---|
| S1 one command starts the app, served by the daemon, opens a browser | delivered (`./zn app [--open]`) | `zn`, `go/cmd/znlive/appd.go`, `client.go`, `go/internal/web/web.go`, `page.go`, `limit.go` | `go test` (AC1), `tests/tooling/app-cli.spec.luau` (AC2) (gate) |
| S2 real data in approvals, workers, stats, tickets, rafts, board, settings | partly: Workers (#732), Approvals (#755, #772) and, beyond the list, Themes home (#763) and read-only ticket, raft and tributary detail views (#788). **Not built:** Stats, Board, Settings, and the Tickets and Rafts list views (still simulated, badge per `f0437.md:50`) | `app/live.js`; routes `go/internal/web/approvals.go:24-28` (state, events, approvals, themes, units); `engine/approvalfacts.luau`, `themefacts.luau`, `themewrite.luau`, `unitsfacts.luau`, `unitswrite.luau` | approval-facts, theme-facts, theme-write, units-facts, units-write, app-md, app-links (node through spec), Go web tests (gate) |
| S3 every view updates without a reload when a step is recorded | delivered **for the real views** (`live.js:1385-1421`: the event stream → refresh; approvals, themes and units refetch; units ETag 304) | | app-live.node.js fetch-list cases (through app-cli.spec) |
| S4 start a worker or dispatch run from the app and watch it in an embedded terminal | **not built** (Implementation step 6, `f0437.md:631`; the unmerged branch `origin/f0437-act-design` holds a step 6a design) | | |
| S5 every item has a place for f0432's talk control | **not built** in the live views (`live.js` has no talk slot; only the mockup's simulated Talk buttons) | | |
| S6 built view by view from the mockup | delivered | `app/index.html` = mockup + 2 edits | `app-copy.spec` |
| P2 no board or settings view | not built. P3 delivered for the real views. P4 not built | | |
| also designed, not built | step 2 (go:embed), step 3 (`/api/tracker`), step 6 slice 3 (what changed since the last approval: AC5, JC1, OC3, G33-G38, G44) | | |

### 2. Document compared with what was built
- Stale or contradictory lines:
  - `f0437.md:59` "Later steps (2 to 6) are listed, not designed. `design: draft` stays." Steps 4a, 5 and 6 now have long designs.
  - There are two different "step 6"s: `:87` (reading a ticket) and `:631` (embedded terminal).
  - "Version 1" claims at `:63, :118, :174` and in G32, against the built version 2 (`approvalfacts.luau:13`, G47).
  - `:280` "Not designed here".
  - The S2 rows of Rules and mutants still say "to build" (`:215-227, :255-259`) though slice 2 is built (`:422-515` records its mutants).
  - The S3 rows (`:228-241, :260-264`), AC5 (`:270`), JC1 (`:272`), OC3 (`:276`), Slices item 3 (`:196`), decision 5 (`:171-184`) and the Touched modules entries `diffsince.luau`, `approvaldiffs.luau`, `diffs.go`, `diff-since.spec`, `approval-diffs.spec` (`:522`) all describe unbuilt slice 3.
  - The Overrides call `tests/tooling` specs "promoted" (`:539-545`).
- ACs: AC1 and AC2 sit at `:614-615`; AC3-AC5 sit inside the Design at `:268-270`. Check lines: AC1 `check.sh:13`, AC2 `:14`, AC3 `:15, :17` (chain), AC4 `:19, :20, :22` (chain). **AC5 has no line**, and its specs do not exist. Steps 4a and 5 have no AC of their own: `theme-facts.spec` and `theme-write.spec` are named by no check line, and `approval-facts.spec` only through AC3.
- Reviews:
  - Idea reviews 001-003, each `revise`, answered "revised".
  - **design-review-001.md** (20 findings, `changes`) is answered only in the table at `:94-115`. There is no `design-refute-001.md`: `./zn rounds f0437 --kind design` says "answer design-review-001.md in design-refute-001.md (every finding gets a line)".
  - G46 mentions a "design review 002 round" for which no file exists.
  - Code reviews of `ff0869d02`, `ae84770e6`, `45de3f1d9`, `4c9d542cc` and `cb7a3799d` are referenced (`:80, :327, :366, :472, :508`), but **no review file was committed**, so `--kind code` sees none.
  - Unmerged `origin/f0437-act-design` carries a *different* `design-review-001.md` (a filename collision if it is ever merged).
- Open to the human (`:655-659`), unruled:
  1. "How much text does the walk carry?" (G40: whole, 400,000 cap, or the 1,500 clip).
  2. "Should the ticket's `pr:` link stay clickable?" (G43).
  3. "Should the contract see a section whole when it holds a fenced heading?" (`bodyOf`; (a) fence-aware rehashes d0295, f0423, c0111, c0172, f0201; (b) refuse such lines).
  
  Also G60 defers to the owner. While these are unruled, z-design refuses the claim.
- Guesses: **61, not approved** (G1-G61).

### 3. Smallest honest split
- **Close now as f0437 ("The app on the daemon: Workers, Approvals, Themes and reading a ticket"):** S1, S6, S3 (for those views), S2 for Workers, Approvals, Themes and the detail views; AC1-AC4; steps 1, 4a, 5, 6.1 and 6.2.
- **New ticket A, "What changed since the last approval":** slice 3 (decision 5, AC5, JC1, OC3, the S3 rule rows), the answers to design-review-001 F3, F5, F6, F7, F15, F16 and F20, and G33-G38 and G44 re-recorded.
- **New ticket B, "The app's remaining views and embedded terminals":** S2's Stats, Board, Settings, and Tickets and Rafts lists; S4; S5's talk slot; P2, P4; steps 2, 3 and 6 (and the `f0437-act-design` design).
- Clean by view and by slice (slice 3's files do not exist). Not clean in two places. First, the slice-3 guesses stay in f0437's guesses.md and are approved with it. Second, the slice-3 findings of design-review-001 must be answered in f0437's `design-refute-001.md` as moved, which needs the owner's Scope decision.

### 4. What blocks closing today, and the work
Blocks today: 3 unruled open questions (the claim is refused), an unanswered design-review-001, no approval of 61 guesses, AC5 with no check line, no raft. Work:
1. Owner rulings on the 3 questions and G60, and the split.
2. Write `design-refute-001.md` (20 lines).
3. Move slice 3 and steps 2, 3 and 6 out; fix the stale lines; mark the S2 rows as killed.
4. Add ACs and check lines for steps 4a and 5 (theme-facts, theme-write, approve-walk, tributaries G24).
5. Two new captures.
6. A design review round on the trimmed document, then approve and the raft layer.

### 5. Estimate and risks
About 450-500 lines (doc about -150/+120, refute about 25, check.sh +3, captures about 60 + 120 including moved design). Rounds: design 1 to 3 (the document is 659 lines and stale in places), code 1, final 2 to 3. Risks:
- Check lines would pin behaviour the open questions may change: Q1 (`approval-facts.spec` "whole sections, hard cap" and the chain's characters-equal oracle), Q2 (`app-live` "pull request is not a link"), Q3, G60, and G24 (against f0422's S2).
- The **chain lines** (`check.sh:17, :22`, `tests/chain/*.sh`) clone the checkout, `git fetch origin main` and depend on the real tracker. They would run at every `./zn finish`, `check` and `done` (twice through the raft's check.sh). Memory says real-work proofs are one-time.
- Approving 61 guesses includes ones for unbuilt slice 3.

---

## Summary

| ticket | closable now? | outcomes delivered / partly / not | remainder ticket | blockers | size |
|---|---|---|---|---|---|
| f0422 | no. After rulings: P1, P2, S4, S7-S9, S1-S3 (ruled), S12 and P4 (ruled to f0420) | 6 (+2 by f0420) / 6 (S1, S2, S3 changed; S5, S6, P3) + D1 partly by f0424 / 2 (S10, S11) + D1's worker mark | "Board: approval band, dependency highlight and graph, waiting for a worker" (S5's approval column, S6, S10, S11, P3, D1 mark) | F4 unruled (claim refused); empty Design; 0 ACs or check lines; inline guess changes scope; Overrides with no chore; no design review; no raft | about 220 lines; design 1-2, code 1, final 1-2 |
| f0423 | no. Step 1 (AC1-AC7, JC1, part of AC14) after the split | 1 (S2a) / 2 (S1 no tributary, S3 via f0420) / 3 (S2b, S5, D1) + S4 is f0420's | "Approval session steps 2-5: wait before final review, rework and lessons, tributary scope, mockups" | no design review ever; 0 check lines; code reviews lost (refutes only); fenced `## W1` leaves 45 Design lines unhashed; Overrides with no chore; no raft | about 290 lines (130 moved); design 1-2, code 1, final 1-2 |
| f0425 | yes, as "the mockup", after `./zn idea` and a Scope decision | P1 + D1-D4 in the mockup / live parts belong to f0437 / none | none | idea unchallenged (claim refused); empty Solution and Design; 0 check lines; red-first impossible | about 90 lines; idea 1-3, final 1-2 (light path) |
| f0437 | no. Steps 1, 4a, 5, 6.1, 6.2 (S1, S3, S6, S2 part) after rulings | 3 (S1, S3 for real views, S6) / 1 (S2) / 2 (S4, S5) + slice 3, steps 2 and 3 | A "What changed since the last approval"; B "The app's remaining views and embedded terminals" | 3 open questions + G60 unruled; design-review-001 has no refute file; 61 guesses unapproved; stale and contradictory Design; AC5 has no line; code reviews lost; chain lines in check.sh | about 450-500 lines; design 1-3, code 1, final 2-3 |

All together: about 1,050-1,100 lines (about 350 of them moved text), one raft for f0422, f0423 and f0437 (one coherence review) plus a light raft for f0425. Every trace code cell would be `none`, because the code is already on main.
