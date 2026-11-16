# Review 001: c0267 (design mode)
Inputs: prep head 3611bf614 (`z-nile/.tracker/issues/c0267/`: c0267.md, check.sh, acceptance/{chain,waiting,wiring,docs}.spec.luau, experiments/{prototype.patch,mutants.py,nostep.sh}); origin/main efa610174 (no Touched file changed since the prototype's base 801e65902); `./zn capture c0267` (b8ee94dbe, no marker); `.cache/dispatch/c0267/answered-1.md`; the prepared or active items whose Touched modules overlap (c0250, f0339, d0295, c0306, c0283).

Runs in this review, all in shared scratch clones under the prep worktree's `.cache/`, push URL disabled:
- Prototype (prep head + `prototype.patch`): `./zn check c0267` gives 10/10 in 59 s. `./zn promote-check c0267` is OK. `stylua --check` and `selene` are clean on the specs and the engine files.
- The 63 fast promoted and tooling specs that read the README, the skills, `dispatch`, `readycheck`, `workread` or `approval`: 395 passed and 2 failed. The two failures, `c0114/docs` (a zz-test lesson naming `scripts/affected`) and `c0120/check-paths` (f0201's and c0292's check.sh), fail the same way on the unmodified prep tree, so neither is c0267's.

### F1 [high] Two prepared items break c0267's sequestered specs in one landing order, and turn its promoted specs red, unnamed, in the other
Where: c0267.md:73 (Checklist, "Prepared preps in flight"); acceptance/waiting.spec.luau:156 and :193; acceptance/wiring.spec.luau:133.
Evidence: The Checklist checks only one direction: do other preps' specs pin what c0267 changes? It never checks whether other preps change what c0267's own specs pin. It names c0250 only for the README sentence, plus d0298 and c0283. I ran both landing orders:
- **c0250** (prepared). Its prototype `proto-c0250` (81b15248) removes `questions` from `readycheck.Raft` and refuses `status == "blocked"` instead (`git show 81b15248:z-nile/engine/readycheck.luau`). I applied c0267's patch on it, keeping both sides of the three conflicts (readycheck `refusal` and the blocked check, the main.luau ctx, the README bullet). Result: `waiting.spec :: AC5: anything else ready refuses for comes first` FAILs at waiting.spec:156-158, the `{ questions = true }` case: `expected nil, got table`. c0267's chain (7), docs (4) and wiring (5) cases pass on that merge, and so do c0250's `dispatch-block`, `work-board` and `docs` specs.
- **f0339** (prepared). Its `experiments/E3-prototype.patch` appends "; approving first needs the issue's explainer page (./zn explain {id})." to `reasonOf`'s no-approval text. It also makes `./zn approve` refuse an issue with no committed `explainer.html`, open the page and ask y/n. I applied it on c0267's prototype and ran c0267's specs:
  - `waiting.spec :: AC6` FAILs at :193 (the byte-for-byte `toBe`);
  - `wiring.spec :: AC7: doing only what the stop says` FAILs at :134 (`approved.ok` is false);
  - `AC8` FAILs at :153 after it.
- **d0295** (prepared). Its prototype adds an Order refusal to `readycheck.reason`. Applied on c0267's prototype, all 16 of c0267's cases pass.

The search the lesson asks for (each open item on origin/main whose `### Touched modules` names one of c0267's engine files) lists items the design never quotes:
`for p in $(git ls-tree -r --name-only origin/main | grep -E '\.tracker/issues/(active/)?[cfd][0-9]{4}/[cfd][0-9]{4}\.md$'); do …grep -oE 'z-nile/engine/(readycheck|workread|dispatch|dispatcher|approval|work)\.luau'…; done`
- c0265, c0275, c0277, c0282: dispatcher (all active);
- c0306 (active, R0107): dispatcher, readycheck, work, workread;
- c0248, c0256: dispatch, dispatcher (both prepared);
- c0250: dispatch, dispatcher, readycheck, work, workread (prepared);
- c0262: dispatch, dispatcher, work, workread (prepared);
- c0291: dispatch (prepared);
- d0295: readycheck, workread (prepared);
- d0298: approval, dispatcher (prepared);
- f0339: approval (prepared);
- c0316: readycheck, workread (new).

Critique: If c0250 or f0339 lands first, a correct c0267 implementation cannot pass its own sequestered `check.sh`, and the executor may not edit it. If c0267 lands first, c0250's or f0339's executor finds a promoted c0267 spec red that its `Overrides:` line does not name. Both paths end in an escalation mid-raft. The tempting fix is to loosen the three assertions, but that does not settle AC7. Under f0339, `./zn approve` itself needs a page, an opener and a y/n answer, so "doing only what the stop says" changes meaning.
Consequences: Fixing the order brings a `depends_on` and the f0339 fixture work below. f0339's approve calls `open`/`xdg-open`, which zz-test's "Caught only by review" list names ("handing work to a process outside the jail"), so the fixture must stub it. An old prepared issue with no page then fails at `./zn approve`, whose refusal names `./zn explain <id>`. And any refusal another item adds to `readycheck.reason` (c0250's `blocked`, d0295's Order, c0306's judged reviews) must sit inside `refusal`, above the approvals flag. Otherwise `waiting` names issues for a raft that `ready` refuses for something else, and the "never asked to approve a raft that could not start" promise (c0267.md:30) breaks.
Recommendation:
1. **c0250.** In `waiting.spec`, replace the `{ questions = true }` case with a refusal that both builds give, for example a member whose `check.sh` has no `check "` line (`designAndCheck`'s gap). Keep `questions = false` in the `Raft` literal: today's type requires it, and promote-check passes with it on the c0250 merge. In Design "Which issues wait" and Implementation step 1, say that c0250's `blocked`, d0295's Order and c0306's `judged` refusals go into `refusal` above the flag.
2. **f0339.** Add `f0339` to `depends_on`, because it changes the command the stop tells the person to run. Then:
   - Write wiring's fixture for f0339's approve: an `explainer.html` from f0339's template whose `zn-contract` is what `./zn explain c0001` prints in the fixture; an `open`/`xdg-open` stub on the fixture's `PATH`; and `y` at approve's prompt through `script`.
   - Have AC6 pin each answer's state-identifying head (`c0001 has no approval: run ./zn approve c0001, then ./zn approve c0001 --publish`, `does not parse: <why>`, `contract changed since approval: <parts>`), not the whole sentence. f0339 and the next rewording can then change the tail without overriding c0267's promoted spec.
   - The other order is the alternative: f0339's prep names c0267's `waiting.spec` and `wiring.spec` on its `Overrides:` line and, being a feature, files the narrowing chore it depends on (z-design, Override check). It costs f0339 more.
   - Either way, the lead tells f0339's and c0250's preps in this round.
3. Paste the search above into the Checklist. For each listed item with a prototype, record the result of c0267's specs on that prototype merged with c0267's (d0295: 16/16, run here).
Lesson: z-design/quote-other-preps-before-promising; z-design/design-the-execution-window

### F2 [high] The user's per-layer outcome is deferred on "Reading by Claude" alone, and three of the named outcomes have no ticket to hold them
Where: c0267.md:22 (the Scope decision of 2026-11-15 and its "Reading by Claude"), :36, :40-43.
Evidence: The Problem's Scope decision quotes the user: "approve the first one and start implementation on it but the two other layers must wait until approved". The Design requires every member's approval before `z-ready` ("every member of the raft, because that is what `./zn ready` requires today", :36). So for a raft of three with only the bottom issue approved, the chain stops before the bottom layer starts. That is AC1's stop with `unapproved = { <layer 2>, <layer 3> }`, at the one place where the user said implementation goes on. The only text in the document that defers this is "Reading by Claude (not the user's words, to confirm at approval)". The relayed ruling, "name, without building, the outcomes of the statement that belong to other tickets" (`answered-1.md`, "Answer to Q1 (user, 2026-11-15)"), lives in an ignored `.cache` file, not in the document. Then :40, :41 and :43 assign per-layer approval, the raft of undesigned tickets and the approval session to "a new ticket, which is the user's to capture". No such tickets exist, so once c0267 is done nothing in the tracker carries them.
Critique: z-design's "Scope is what was captured" (and review item 11): an outcome in the Problem's Scope decision line that is deferred without a `Scope decision`/`Decided with the user` line deferring it is high. The tempting fix is a sentence saying "per the user these belong to other tickets". It leaves the outcomes homeless, because z-design says a split "moves outcomes into new issues captured through z-ticket … the original Problem gains a `Scope decision` line naming the new ids".
Consequences: Every option has to cover the multi-member behaviour, not only the unbuilt extras: that is where c0267's stop contradicts the user's words. Per the user's 2026-11-15 rule (design on, label guesses, walk through them at approval), this can be put to the user as a labelled guess at the approval session rather than as a stop. But it has to sit in one list the session reads.
Recommendation: escalate to the user: (as a labelled guess for the approval session, the author's to place) with these options:
- **(a)** Keep the design. Record answered-1.md's ruling in the Problem as a `Decided with the user (2026-11-15)` line. Capture the three uncaptured outcomes now as draft issues (`./zn new issue …`, z-ticket) and name their ids in that line. Add one guess under a `### Guesses for the approval` heading: "a raft of several issues waits for all of them; per-layer start is <new id>'s". Cost: three captures, no code.
- **(b)** Build per-layer start in c0267:
  - `ready` requires only the bottom layer's approval;
  - `./zn start` refuses a layer whose issue's approval does not hold;
  - the chain's wait moves from before `z-ready` to before each layer's start, inside z-run.

  Cost: `readycheck`'s member set, `cmd.start`, the z-run stop, overrides of the specs that pin "every member" (`tests/tooling/ready-members.spec.luau`, `c0067/ready.spec.luau`; confirm by a suite run) and the slow tier re-run. Roughly 200 to 300 more lines.
- **(c)** Write the reading as a `## Open to the human` bullet, which stops the chain until it is ruled.

### F3 [medium] The stop's commands cannot get an issue with an unreadable approval through
Where: c0267.md:51 (`waitingWhy`), :169 (AC1), :175 (AC7), :163 (the `reasoned` row); `z-nile/engine/approval.luau:157-159`.
Evidence: For `state == "bad"` the stop prints the same line as for `none`: `… && ./zn approve <id> && ./zn approve <id> --publish`. `./zn approve` writes through `approval.append`, which refuses to add a row to a file that does not parse. I ran `approval.append` on an issue folder whose `approval.md` is `not an approval`, and it returns `nil z-nile/.tracker/issues/c0001/approval.md does not parse: the first lines must be the approval header`. The person follows the stop and is refused, and the stop also drops the parse error that `stateOf` returns (`Unapproved` has no field for it). AC7 runs the way through for `none` only.
Critique: AC1 says the text names "the command line that approves each". For `bad`, it names one that fails. The tempting fix is to print the parse error and stop there. That still leaves the person without a way through.
Consequences: `--publish` may replace `approval.md` (`publish.luau:449-458`), and approve's dirty check covers only the contract's paths. So removing the bad file in the fresh worktree and approving again works. The unreadable rows are dropped, but they were already unreadable, and c0283's `approved` row keeps the history. Under F1's f0339 order the line needs the page too.
Recommendation:
- `Unapproved` gains `why: string?` (stateOf's third value) and `file: string` (the member's `approvalFile`), and `readycheck.waiting` fills both.
- For `bad`, `waitingWhy` prints `<id>: its approval.md does not parse (<why>); ./zn approve refuses to add to it, so its line removes it first.` and that issue's line inserts `git rm -q <file> && git commit -qm "tracker: drop <id>'s unreadable approval.md" &&` before `./zn approve <id>`.
- chain AC1 asserts both. wiring gains a case where origin/main holds an unparseable `approval.md`, the stop names it, and running that line (fixed name) gets `next: z-ready`.
Lesson: z-design/dispatched-refusals-name-their-way-through

### F4 [medium] The fail-safe and the layer order are pinned only on the pure functions, not where the dispatcher feeds them
Where: c0267.md:52 ("fails closed rather than readying"), :60-61 (`workread.unapproved`, `dispatcher.facts`'s `"no answer"`), :156 (the order row); chain.spec AC2; wiring.spec:38 (`issues: [{ID}]`).
Evidence: I applied two mutants together to the prototype:
- `dispatcher.facts`: `unapproved, unreadable = ctx.approvals(id)` plus the `"no answer"` fallback replaced by `unapproved = (ctx.approvals(id))`;
- `workread.unapproved`: both `return nil, <why>` lines replaced by `return {}, nil`.

Then chain, waiting and wiring give `16 passed, 0 failed`. A failed read now becomes `z-ready`, and no case notices. The same holds for order: `blockFor` passes `fact.issues` as the order, but wiring's raft has one member (wiring.spec:38), so a caller that passes `{}` or `listed` instead also passes.
Critique: AC2's "unreadable stops as a failure" holds for `dispatch.next` but not for the code that sets the field. The tempting fix is a pure case on `dispatch.next` again, which already exists.
Consequences: To pin the act site, the fallbacks need a seam a spec can reach without the real repository. `dispatcher.facts` reads git through `rootsAt`, and `workread` reads the process's cwd. The lazy read ("only for a backlog prepared raft") is a fail-safe too.
Recommendation:
- Extract `dispatcher.approvalFacts(ctx, o, kind, id): (unapproved, unreadable)` and `workread.unapprovedFrom(ok, input, id)` as pure functions, and spec them directly:
  - `approvals` answering `(nil, nil)` gives `unreadable = "no answer"`; `(nil, "x")` gives `"x"`;
  - a `pcall` failure or a missing raft gives `nil` and why, never `{}`;
  - a ctx whose `approvals` errors is never called for an issue or an active raft.
- Add a two-issue raft to wiring whose Order puts c0002 before c0001, and assert the stop names c0002 first.
- Add the three act-site mutants to Rules and mutants.
Lesson: zz-test/pin-fail-safes-where-they-act

### F5 [medium] The stop is one line whose last command ends in a period, and every approval leaves a worktree and branch nothing removes
Where: c0267.md:51 (`waitingWhy`), :163 (the `reasoned` row); `main.luau:4349` (worktree-prune).
Evidence: The prototype's `dispatch.waitingWhy("R0050", {c0010 none, c0011 changed})`, run, prints one line:
`… for each: cd "$(./zn worktree approve-c0010-$(date +%s) --from origin/main)" && ./zn approve c0010 && ./zn approve c0010 --publish; cd "$(… approve-c0011-…)" && ./zn approve c0011 && ./zn approve c0011 --publish. Then run ./zn dispatch R0050 again.`
- The last command copied as printed ends `--publish.`, which `approve` rejects (`usage: approve <issue-id> [--check|--publish] (unknown option --publish.)`) after `./zn approve` has already committed the approval. Rerunning the line makes a new worktree from origin/main and asks for approval again.
- `./zn worktree-prune` keeps every `approve-<id>-<epoch>` worktree (`kept … (named worktree: remove it when its PR has merged)`), and such worktrees never get a PR. An approval session of N designs leaves N worktrees and N branches.
- The row "the stop's commands, followed, get the raft to `z-ready`" is `reasoned`: wiring reruns the steps by hand with a fixed name, never the printed text.
Critique: The stop exists to hand the person literal commands. The tempting fix is to drop the trailing period, which leaves the leftovers and the unrun text.
Consequences: Cleaning up runs `git worktree remove` and `git branch -D` in the person's own main checkout, the ordinary cleanup `worktree-prune` does for rafts. It has to be forced (`-D`) because publish makes its own commit, and it must run only after `--publish` succeeded, so a failure keeps the worktree for a retry.
Recommendation:
- `waitingWhy` returns lines: the reason, one line per issue, `In a terminal of your own, from the main checkout, run each line:`, one command per line with nothing after it, then `Then run ./zn dispatch <R> again.`
- Each command is `w="$(./zn worktree approve-<id>-$(date +%s) --from origin/main)" && (cd "$w" && ./zn approve <id> && ./zn approve <id> --publish) && git worktree remove "$w" && git branch -D "${w##*/}"`. The subshell returns to the main checkout, so "for each" holds literally.
- chain AC1 asserts each command is a whole line of `why`. wiring AC7 runs the printed line itself (`script -q /dev/null bash -c '<line>'` from the fixture's main checkout) and asserts `next: z-ready` and no `approve-c0001-` left in `git worktree list`. The row becomes `run`.

### F6 [low] `Action.waiting` names readers that cannot see it
Where: c0267.md:50, :86.
Evidence: `waiting` is said to be "for a reader (status, the board)". But the stop records nothing: the chain only saves its state, which is the design's own "no `retry`" argument. `./zn dispatch status` and the board read `state.json`, so neither can ever see `waiting`.
Recommendation: Rewrite :50 to say the field is for the in-process caller only. Showing "waiting for the person" on the board or in `dispatch status` would need it saved in `state.json`, and that is the worker end's or the board's (c0253, c0118).

### F7 [low] Implementation step 3's command has the wrong path and no bound, and wiring's header names a file that does not exist
Where: c0267.md:189 (step 3); wiring.spec.luau:9; c0267.md:109 (E5).
Evidence:
- Step 3 says to run `bash z-nile/.tracker/issues/c0267/experiments/nostep.sh …` "from `z-nile/`". From there that path is `z-nile/z-nile/…`, and during execution the issue sits in `issues/active/c0267`. The slow specs it runs (827 s and more) also go unbounded: the PreToolUse hook refused my background `bash …/nostep.sh lune run tests/run …` ("`bash` is not" bounded).
- wiring.spec:9 says check.sh runs it "through acceptance/nostep.sh". The file is `experiments/nostep.sh`, and check.sh uses its own `nostep` function.
- E5 does not record that `mutants.py` ran under `./zn run`.
Recommendation: Step 3 should read `./zn run --time 1800 -- bash "$(./zn find c0267)/experiments/nostep.sh" lune run tests/run -- <spec>` from `z-nile/`, after checking `./zn find`'s output form. Fix the header comment, and record E5's bound.

### F8 [low] `Overrides: none` rests on a grep-chosen subset, not the affected run on the prototype
Where: c0267.md:102, :108 (E4), :120.
Evidence: E4 ran "the 25 fast specs that grep for …" plus seven slow ones. The selector picks 228 specs. My run of the 63 fast specs that read the touched docs and modules found no override (above), but the specs the selector picks through `main.luau` alone were run by neither of us.
Recommendation: Run `z-nile/check.sh --affected` once on the prototype in a scratch clone before the prep commit, and record the counts and the failures that are also red on the base.
Lesson: z-design/confirm-overrides-with-a-suite-run

### F9 [low] `ready`'s refusal and z-ready's skill call the dispatched path a one-time legacy step, and AC6 would promote that text
Where: approval.luau:123; z-nile/skills/z-ready/SKILL.md:11; waiting.spec:193-194.
Evidence: After c0267, a dispatched design is prepared and rafted before approval as the normal path. `./zn ready` and `./zn work next` still say "from the worktree that holds the design. This is a one-time step for an item prepared before approval." After the merge, no worktree holds the design. z-ready:11 says the same, and AC6 pins the sentence byte for byte in a spec that `done` promotes.
Recommendation: Reword the no-approval refusal and z-ready:11 to the path the stop names: approve in a worktree on origin/main, then `--publish`. Change `tests/tooling/approve.spec.luau:116`, the one spec that pins the old words (`git grep -nF "one-time step"`), as a tooling spec the executor may change. Do it together with F1's f0339 decision, since f0339 appends to the same sentence.
Lesson: z-design/restated-rules-move-together

Candidate lesson (for the lead to harvest): z-design/quote-other-preps-before-promising should also ask "has this design's own sequestered spec been run on each in-flight prototype that changes a module it builds literals of (`readycheck.Raft`, a refusal text), not only searched for their specs pinning this one's change?". This round's c0250 and f0339 collisions were one-directional misses.

Verdict: changes
