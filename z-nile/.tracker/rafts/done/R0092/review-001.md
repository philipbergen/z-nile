# Review 001: R0092 (code mode)
Inputs: layer `R0092/1/c0264` at f584b9a32 ("c0264: README states z-nile's intent") against origin/main 0587e37e3 (its merge base, after `./zn sync --fetch`); `git diff origin/main...HEAD`; `c0264.md`, `c0264/check.sh`, `c0264/acceptance/*.spec.luau`, `experiments/README.draft.md` and `README.base.md`; `R0092.md` and `R0092/check.sh`; to check the *exists* sentences: `z-nile/skills/z-work/SKILL.md`, `z-nile/engine/work.luau` (#330), `.models.toml` (#339), `z-nile/engine/trace.luau`, `z-nile/engine/contract.luau`.

Commands run:
- `./zn check c0264`: 10/10.
- `./zn check R0092`: 3/3 (the affected RC0 gate, c0264's checks, `promote-check`).
- `z-nile/check.sh --affected`: GATE PASSED in 9.9 s, "no specs affected" in all seven homes (see F2).
- The 17 specs that read the README, run directly from `z-nile/` (`lune run tests/run -- tests/acceptance/{c0082/audit,c0115/docs,c0115/layout,c0115/readme,c0116/docs,c0117/docs,c0118/docs,c0120/graph-homes,c0165/select,c0183/docs,c0184/docs,c0185/docs,c0185/graph,c0246/paths,c0259/readme}.spec.luau tests/tooling/{affected,watch}.spec.luau`): 111 passed, 0 failed.
- `./zn approve c0264 --check`: the approval holds (1e0ab8f2…, 2026-11-14T08:18:49Z).

Sequestration: the zz-review command lists one path, `A z-nile/.tracker/issues/active/c0264/acceptance/watch.txt` (content `z-nile/tests/lib/t.luau`). `./zn finish` wrote it (`watchcmd.capture`, main.luau:3775; zz-test Capture calls finish "the only writer"). It is not an input of the approval contract (contract.luau:12), and c0193's and c0256's layers added the same file. No `check.sh` or spec changed. Not a finding. There is no `Prep reference`, because no check here judges sequestered files against a prep commit.

Draft against delivery (Implementation step 5): `diff experiments/README.draft.md z-nile/README.md` shows two kinds of change.
- 30 state words go from *captured* to *designed* for c0248, c0250, c0263, c0265, c0274 to c0277, c0280 and c0282 to c0284. Each is `design: ready` in the tracker.
- One prose edit adds c0256 to the outside dependencies of the c0248 to c0254 raft. c0250's prep (84e0f15fb) gave it `depends_on: [.., c0256, ..]`, and c0256 is not done. Without it, AC7's `raftdeps` fails, and the Design's Roadmap bullet says the prose names every outside dependency. The edit is recorded in the Verification log, and AC6's pinned run `c0257, c0260, … and the heartbeat tickets` is intact. I accept it.

I spot-checked the newly *designed* sentences against each ticket's Solution: c0250, c0263, c0265, c0274, c0276, c0277 (including #344's re-ready revision), c0280, c0282, c0283 and c0284. Each matches. I also spot-checked these *exists* sentences:
- the roles table against `.models.toml`. #339 moved `final-review` to another model, and the README names none, so the sentence is still true.
- the `./zn trace` and `final-review` refusal.
- the idea gate.
- z-work, which fails (F1).

### F1 [medium] The worker's `*exists*` sentence says an unnamed z-work session stops after one raft, but since #330 it keeps taking the next one
Where: `z-nile/README.md:76` (### The worker, first sentence). The same staleness sits outside the two sections at `z-nile/README.md:210` (skills table) and `:246` (The five parts, step 5).
Evidence: README:76 says "that session takes the next prepared raft, or the one named (`./zn work <R>`), says what it took, and carries it layer by layer to `./zn done`, then stops. *exists*". PR #330 (50c313e6d) changed that. It landed 2026-11-13 17:02 PST, six minutes before c0264's prep #326 (17:08), so the draft never saw it. What main says now:
- `z-work/SKILL.md`'s description: "With no raft, the session keeps taking the next one ready would accept. With a raft named, it carries that one and then stops".
- Its step 6: "When the line says end and no raft was named … run `./zn work next` with no raft".
- `z-nile/engine/work.luau:21-24`: "A person who names no raft keeps taking the next claimable one … A named raft ends the session". It stops after `work.BLOCKED_IN_A_ROW` = 2 releases in a row (work.luau:69, :359).

So the delivered README tells a reader that main's worker does not go on to the next raft. The user asked for exactly that rule to be stated explicitly. Neither guard sees the error. AC7 judges where labels sit and their states, not what an `*exists*` sentence claims. Step 5's draft diff can't catch it either, because the draft predates #330.
Critique: There are two tempting fixes, and neither works.
- Leave it, because main's README said the same before. But this raft wrote this sentence and moved it into The worker (Merge rules: "#318's sentence is the first sentence of The worker, labelled *exists*"). And the Design's Usability says a reader "can tell what main does today from what is planned".
- Relabel the c0253 bullet ("A worker clears its context and picks up the next raft whenever a raft ends") *exists*. That is wrong, because clearing the context is not built: z-work step 8 says no CLI lets the session clear itself, and work.luau:25 says "A supervisor that starts a fresh session is a later ticket".
Consequences:
- The reword differs from the draft for a reason step 5 doesn't list (main's behaviour changed, not the README), so the Verification log must record it as a deviation.
- AC6: the sentence holds only one pinned phrase, `z-work`, which appears four more times. The regexes forbid model names and tier words in The worker, and the new text needs neither.
- AC7: the label place stays `The worker|-` as long as the sentence keeps one `*exists*` and no id.
- AC4 and AC5 read only labels and bullets, so they are unaffected.
- README:210 ("one raft … until it lands or is released") and README:246 ("The session ends when the raft lands or is released") are just as stale, but AC8 keeps them out of this raft.
Recommendation:
- Reword README:76 only, keeping its single `*exists*`, to say what main does:
  - With a raft named (`./zn work <R>`), the session carries it layer by layer to `./zn done` and stops.
  - With none named, it takes the next raft `ready` would accept and says what it took. It carries that raft to `./zn done`, then takes the next one in the same context. It stops when no raft is claimable, or after two rafts in a row are released as blocked.
- Leave the c0253 bullets and labels alone: clearing the context, the wait loop and the headless launcher are not built.
- Re-run `./zn check c0264` (10/10) and the 17 README specs listed in Inputs.
- In the Verification log, record the deviation from the draft and its reason: #330 landed after the draft was frozen.
- Capture a chore for README:210 and :246 (z-ticket, `--project z-nile`).
- Leave the Design as approved: the approval hash covers it.
Lesson: z-design/status-labels-need-a-tracker-fact

### F2 [low] The Verification log records no gate run, and the gate it should record ran no specs
Where: `c0264.md:240` (Verification log); the Design's "Affected specs" (`c0264.md:151`) and Regression guard (`c0264.md:167`).
Evidence: The Design says `lune run z-nile/affected -- z-nile/README.md` "prints `ALL`: any README change selects the whole suite". Today it prints nothing: `watch.isSource` drops every `.md` (`z-nile/lib/watch.luau:50`), and zz-test says "a document selects nothing". The effects:
- `z-nile/check.sh --affected` and RC0 report "no specs affected" in every home.
- `./zn finish` wrote an empty `results.txt`.
- The finished `acceptance/watch.txt` names only `z-nile/tests/lib/t.luau`.

The Regression guard ("every promoted README spec stay green (E2)") therefore rests on E2 from 2026-11-12, before this layer's 30 state changes and the c0256 edit. The log says only "`./zn check c0264`: 10/10"; it has no gate run (step 4).
Critique: Nothing before the merge runs the 17 promoted specs that read the README, because a tooling-only PR is gated by `--affected` (zz-execute Phase 5). Only the watch-net after landing would run them. This review ran them, and all 111 cases pass. The tempting fix is to correct the Design's "prints ALL". But the Design section is an input of the approval hash (contract.luau), so the edit voids the approval and `./zn done` refuses. The empty `results.txt` does not block the final review: `trace --check` accepts a `check.sh` command line as the test cell (trace.luau:1042-1051).
Consequences: none beyond the log lines.
Recommendation: Add to the Verification log:
- step 4's gate: `z-nile/check.sh --affected` passed with no specs selected for a README-only change, so the Design's "prints ALL" no longer holds.
- a direct run, after F1's edit, of the 17 specs listed in Inputs, with the counts.

Leave the Design as it was approved.

Lesson candidates (for the lead to harvest; a reviewer writes none):
- zz-review, Sequestration: `./zn finish` always adds `acceptance/watch.txt` to the ticket's sequestered folder, so the review's command lists an `A` on every finished layer, while the skill says anything but `R100` is high. Rule: the one allowed non-rename is that finish-written file. Check: is every non-`R100` path the command lists the ticket's `acceptance/watch.txt`, and does it parse as a watch list?
- zz-execute or zz-test, documentation layers: the affected gate selects no spec for a change made only of `.md` files. So the promoted specs that read the document run nowhere before the merge, and a design's "selects ALL" claim from before the watch map is stale. Check: when this layer changes only documents, which promoted specs read them, and were they run directly and recorded?
- z-design, *exists* sentences drafted before the prep lands: before delivery, list the non-tracker commits on main since the draft froze (`git log <draft-commit>..origin/main -- . ':!*/.tracker/*'`), and re-read each `*exists*` sentence whose subject one of them changed (F1).

## Judged criteria (code mode only)
None: c0264 has no Judged criteria.

Verdict: changes
