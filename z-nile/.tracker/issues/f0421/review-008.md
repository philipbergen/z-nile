# Review 008: f0421 (code mode)
Inputs: origin/f0421-s1b e429b82b4 against origin/main 2eca5afd2 (merge base fe721531a), fetched. Round 2: `review-007.md`, `refute-007.md`, and `git diff 70c39ad8f origin/f0421-s1b` over `.models.toml`, `z-nile/engine`, `z-nile/tests`, `z-nile/skills` and the ticket folder (16 files): `models.luau` (the match, the author pass, `resolveAlias`), `rollout-gate.sh`, `models-alternatives.spec.luau` (new), `model-cmd.spec.luau`, `models-pin.spec.luau`, `models-catalog.spec.luau`, the root file and its fixture, zz-rules, `f0421.md`. Not run, as the brief asked: the gate, `./zn check f0421`, the spec runner.

Probes (read-only, each through `./zn run --time 30..170`, on fresh `git archive` copies in the reviewer's scratch folder: `main2/` 2eca5afd2, `branch2/` e429b82b4, `mut2/` for mutants):
- P1, every answer again (`probes/probe.luau`, now 55 candidate `ZN_MODEL` ids, with folded cases, a trailing space and `-fast`): 56,805 lines on main's engine and root, 57,909 on the branch's.
- P2, main's engine on the branch's root and the branch's engine on main's root.
- P5, `rollout-gate.sh layer.catalog`, the reviewer's own list by each head's engine text (`probes/behave.sh`), a list of worktrees that hold the catalog reader without S1a's squash (`probes/behave2.sh`), and the script with a `gh` that fails, with no mark, and with a wrong mark and a wrong second argument.
- P6, the small runner: the two acceptance specs, `models-pin`, `models-catalog`, `models-identity`, `models-review-table`, `models-alternatives`, `models-activities`, `rounds`, `c0117/models`, `review-record`: 125 cases, all green; `model-cmd` 19 of 20 (the one failure is the runner's, which does not clear the session variables). 15 mutants on `mut2/`, each restored.
- P7, single answers (`probes/extra.luau`), and two new probes of a single-form entry through the gate (`probes/single.luau`, `probes/specfix.luau`).
- `stylua --check` on seven changed Luau files, `selene` on three, `lune run z-nile/watch-check` on the copy: clean.

## The findings of review-007, one line each
- F1: fixed. P7: an Opus session with an Opus writer gives `same=true writer=claude-opus-5-5-high` and the line ends `same-model=yes`; with an Argon writer `same-model=no`; Sonnet at easy likewise; an Argon session is unchanged. M23 reversed is killed by `models-alternatives` :: F1 and by model-cmd's new case, M14 by F1's first case. The dispatcher's lines are the same as in round 1 (0 differing), and claude's are the same as on main (0 differing).
- F2: fixed. The script decides by each head's own engine text and names 19 of 170 heads (eight worktrees, eleven pull requests), which is the reviewer's own list exactly; `agy-cli` and `d0434-follow` are gone. No worktree holds the catalog reader without S1a's squash. With a `gh` that fails it exits 3 and names nothing; with no mark it exits 1. What is left is F2 below.
- F3: fixed for the root. A root edit that is not re-pinned turns `models-pin`'s tie red (N2). Agent given `offers` turns the tie and the live-root case red (N3), and the live-root case stays red when the fixture is edited with the root (X1). The final review lowered to heavy in both files turns it red by name (X2). A closer file is still seen by no case: the design's rule and Risks hold it, as round 1 recommended, and none exists.
- F4: fixed. M11, M12, M13, M14, M17, M20 and M26 are each killed, M20 at the command. The cut to the exact id left the gate and the waiting line on the bare model: F1 below.
- F5: fixed for `resolveAlias` (N1 killed; grok with no light table answers `grok-4.7@high` both ways; the review list in its place is killed too, X3). `specFor`'s model branch is under "Step two owes" with the closer example, which is still refused (P7), as recorded.
- F6: escalated as recommended, and still open to the human. It is recorded under `## Open to the human` as `review-007 F6`, tied to G28. The sequestered files equal the design branch's (6f0319936). Since 741bc6cd7 only three comment lines of `s1b-rules`' header changed, on the design branch, and no case. The three-dot diff still lists the six paths until the design merges apart or the owner rules.
- F7: fixed (the root file's two comments, zz-rules, models-catalog's header and titles, AC34, the seed's line, the touched list and the size).
- F8: fixed. B1 to B14 are listed and the gate's results recorded. One entry is garbled: F3 below.

### F1 [medium] The gate before every command and the waiting line still name an entry by its bare model, so an entry written with a separate effort can be reached by no `ZN_MODEL`
Where: `z-nile/engine/models.luau:1758` and `:2150` (the match, `entryId(e) == session`), `:1848-1849` (`modelsIn` collects `e.model`), `:2016` (the waiting line names `e.model`); `z-nile/engine/modelcmd.luau:71` and `:88` (`sessionModel` gates on `modelsOf`); `z-nile/tests/tooling/models-alternatives.spec.luau:119-129`; C1 in `f0421.md`; zz-rules, "a session delivers the entry whose id is exactly its `ZN_MODEL`"
Evidence: `probes/specfix.luau`, on the fixture the new F4 (C1) case builds itself (agent with `heavy = { model = "claude-opus-5-5", effort = "high" }` and a two-entry light list in the same form). `modelsOf` is `claude-opus-5-5,claude-sonnet-5-5`. `ZN_MODEL=claude-opus-5-5-high`, the id the case shows resolving: `modelcmd.sessionModel` refuses it, `is placed at heavy, and no list of clis.agent in .models.toml holds it: ... start agent on one of claude-opus-5-5, claude-sonnet-5-5`, so `./zn model` exits 2, the registration's can-list is empty and `work next` hands out nothing. `ZN_MODEL=claude-opus-5-5`, the id that refusal and the waiting line offer: the gate accepts it, `resolveActivity` gives nothing at any level, and `lacks("code", "risky")` is `code/risky (heavy: claude, agent running claude-opus-5-5, ...)`: a session that says it runs `claude-opus-5-5` waits for a worker running `claude-opus-5-5`. On that table no session of agent delivers anything. `probes/single.luau`, a closer `[clis.agy] heavy = { model = "gemini-4-neon", effort = "high" }`: on main's engine `ZN_MODEL=gemini-4-neon` is accepted and delivers the nine heavy pairs; on the branch it is accepted and delivers none, and `gemini-4-neon-high` is refused with the same false words. The single form with an effort is one of C5's entry forms. The case passes because it asks `resolveActivity`, `resolveAlias` and `canList`, never the gate, and its agy fixture keeps the id string in the review list, which puts the id in `modelsOf`. The live root cannot reach this: every agy entry is an id string and agent holds one model (P1: the five Neon and Argon sessions that work on main today answer the same, gate and can-list).
Critique: Round 1 asked for the bare-model clause to go and did not say what else names an entry. Three places do, with two definitions. Step two is where it bites: agent keeping a table entry in the single form once it holds a second model.
Consequences: `modelsOf` cannot change: the pin's `models` lines and `s1b-rules` hold claude's and agent's bare models. The ids a session may name are a second list, the entries' ids. On the seed and the frozen root every agy id is its model, so no pinned line moves. `needsSession` still counts bare models, so two efforts of one model in the single form count as one; that is main's behaviour and can stay until step two.
Recommendation: One function gives the ids a session of a CLI may name (each entry's `entryId`). `sessionModel` gates on it and offers it as the way out, and the waiting line names it. Tooling cases on the spec's own two fixtures, through `modelcmd.sessionModel` and `workerlive.capability`: the exact id passes the gate and is handed its pairs; the bare model is refused by the gate, and the way out names ids; the waiting line names the id a session must set.
Erred: zz-review
Upstream: none

### F2 [low] The gate script names nothing when its second argument is mistyped, and exits 0 whether or not it names a head
Where: `z-nile/.tracker/issues/f0421/rollout-gate.sh` lines 15, 27-31 and 55
Evidence: P5. `rollout-gate.sh layer.catalog "no-such-text"` prints `0 named of 170 heads` with exit 0. A wrong mark errs the safe way (34 named). With 19 heads named the exit code is 0, as with none.
Critique: The later gates the design gives this script pass their own texts, and the one that says "reads today's root" changes once S1b is on main.
Consequences: none
Recommendation: Exit 2 when origin/main's own engine does not hold the second argument, and exit 1 when a head is named.
Erred: zz-execute
Upstream: z-design

### F3 [low] One entry of the verification log has the gate's output pasted into the middle of a command
Where: `f0421.md` lines 898-920
Evidence: "The gate on 70c39ad8f: `ZN_    names each head whose ...`", then 21 lines of the rollout script's output, then "`_WAIT=2400 z-nile/check.sh --affected` passed: 471 passed, 0 failed, 45 spec files." The pasted block is this round's output (it names `agy-cli`), under a line about round 1's commit.
Critique: The step-one gate result cannot be read as written.
Consequences: none
Recommendation: Restore the line (`ZN_GATE_WAIT=2400 z-nile/check.sh --affected` on 70c39ad8f) and drop the pasted block; the rollout output stays in this round's entry.
Erred: zz-execute
Upstream: none

## Judged criteria (code mode only)
None: the ticket's Judged section says "None."

## The five points
1. The one change. P1: claude (334 lines), grok (193), agent (193) and kimi (193) have 0 differing answers in their own blocks, and no line outside agy differs once the text after `agy running` is set aside; agy goes from 381 to 569 lines and 28 of 105 activity lines change, as in round 1. The exact-id match changes no answer for a session that works on main today: the five ids main accepts for agy (`gemini-4-neon-low`, `-medium`, `-high`, `gemini-4-argon-medium`, `-high`) pass the gate and give the same can-lists; agent, kimi and grok ignore the variable; a folded case, a trailing space and `-fast` are refused on main and here. The branch's engine on main's root: 0 of 56,805 lines differ. The one table form whose answer does change is F1's, which the live root does not hold.
2. F1's fix. Claude's lines equal main's (1,176 `same-model=yes` lines on each side). The dispatcher's pick is the same as in round 1 for every CLI, and the same as main for claude, grok, agent and kimi. Only agy sessions on Opus and Sonnet change, on review activities.
3. F3's cases. They bind the root: four root edits, each a different way to the final review, turn a case red, also when the fixture is edited with the root. A closer file can still do it with no case red; no closer `.models.toml` exists on main, on the branch or on any remote branch, and one changes only by a pull request a person merges.
4. The gate. Its set is right: 19 of 170, checked a second way. It fails when `gh` fails. F2 is the remainder.
5. Mutants. All eight earlier survivors and N1 to N3 rerun, and four more (X1 to X4): 15 of 15 killed.

Merge safety. Once the 19 heads the script names have merged main (rerun it just before the merge: heads move), the merge is safe for running sessions of the five CLIs: no answer changes for claude, grok, agent or kimi, none for agy sessions on Neon or Argon, S1a's engine reads the new root with 0 lines changed, and no other head reads today's root and not the seed. F1 is not a hazard of this merge: the live root cannot reach it and the pin's tie now holds the root to the seed. It is a defect to close before a table gives a session CLI an entry with a separate effort, which step two's agent may. F6 is still the owner's to rule.

Verdict: changes
