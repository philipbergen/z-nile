# Review 002: d0328 (design mode)
Inputs: prep worktree `.worktree/prep-spend-session-cwd-slash` at 678894d6e with its uncommitted `d0328.md`, `check.sh`, `acceptance/spend-session-cwd.spec.luau`, `acceptance/spend-session-dot.spec.luau`, `experiments/prototype.patch`, `harvest.md`, `design-review-001.md`, `design-refute-001.md`; `z-nile/engine/sessionread.luau` as on main (lines 131-202 `span`, 205-230 `running`, 259-266 `claudeDirs`); capture commit 3cadd2cef (the newest `tracker: new` commit naming d0328, the version `./zn capture` prints by z-design SKILL.md:10; `./zn capture` itself was refused by the session's permission classifier, so I read the commit with `git show`) and idea commit 3290615a3 with `idea-review-001.md` / `idea-refute-001.md`; `~/.claude/projects`, `~/.cursor/projects` and `~/.grok/sessions` on this machine (listed, read only).

Checks run (all specs through `./zn run --time 300 -- lune run tests/run -- ...` from `z-nile/`):
- Unpatched engine: AC1 fails at spend-session-cwd.spec:38 and AC2 at spend-session-dot.spec:37, both `expected "claude-opus-4", got nil` (E3 holds).
- `experiments/prototype.patch` applied: both specs `1 passed, 0 failed` (E1 holds); `tests/tooling/work.spec.luau` `14 passed, 0 failed` (the Regression guard's `span` and `claudeDirs` cases stay green).
- Mutants on the prototype's line 142: no strip fails AC1 and AC2; `/` only fails AC1 and AC2; `/%.` to `--` then `/` passes AC1, fails AC2; `%.worktree` to `-worktree` then `/` (round 1 F3's hard-coded mutant) passes AC1, fails AC2; `[^%w%-]` (the wider rule of open bullet F1) passes both, so the specs do not prejudge the human's F1 ruling. E2's recorded outcomes hold.
- Engine reverted with `git checkout -- z-nile/engine/sessionread.luau`; `git status` shows no engine change.
- `ls ~/.claude/projects`: 133 `…pickman--worktree…` folders, none `…pickman-.worktree…`, none holding a character outside `[A-Za-z0-9-]`. `ls ~/.cursor/projects`: 0 of 21 end in `-`. `ls ~/.grok/sessions`: 0 of 22 end in `%2F`.

Round 1 answers:
- F1: escalated, not fixed: AC2's `_` case is gone (no spec pins `_`), and the rule question is open bullet 1. Closed as an escalation; the bullet's wording is F2 below.
- F2: escalated: `running` is now under Siblings (d0328.md:35) and open bullet 2. The sibling list is still incomplete (F1 below), and the bullet leaves out a cost (F3 below).
- F3: fixed and verified: AC2 (d0328.md:98, spend-session-dot.spec.luau:36) kills both the `/%.` mutant and the `.worktree` hard-code.
- F4: fixed: one spec file per check (check.sh:12-13); AC1 names `sessionread.span` (d0328.md:97).
- F5: fixed: `experiments/prototype.patch` exists and reproduces E1/E2; the affected list (d0328.md:46-65) has 20 entries and line 44 says 20.

### F1 [medium] The revised Siblings bullet still misses two folders `span` builds from the same unstripped cwd: the grok folder and the cursor folder both miss every session of a cwd ending in `/`
Where: d0328.md:35 (Siblings, revised in answer to round 1 F2); sessionread.luau:152 (`grokDir`) and 173 (`cursorKey`).
Evidence: `span` receives `process.cwd` with its trailing `/` (main.luau:7560; the capture's Problem: "Lune's process.cwd ends in '/'"). The prototype strips it only inside `claudeKey`, so the grok and cursor keys keep it. For `/a/b/` the grok folder is `~/.grok/sessions/%2Fa%2Fb%2F` (`encode` turns the trailing `/` into `%2F`) and the cursor folder `~/.cursor/projects/a-b-/agent-transcripts`. No folder on this machine has either spelling: none of the 22 grok session folders ends in `%2F` and none of the 21 cursor project folders ends in `-` (e.g. `Users-philipbergen-code-pickman`). So `./zn spend` from any checkout also records no grok or cursor session: the same mistake as the Claude case. Siblings says "`sessionread.encode` (the grok folder) and `claudeDirs` keep their mappings", which is true of `encode`'s mapping but hides that `span` hands it the unstripped cwd, and it does not name `cursorKey` at all. The defect checklist (`z-nile/skills/z-design/checklists/defect.md:7`) requires every place with the same mistake to be fixed here or captured, and round 1 F2's Recommendation asked for exactly that list. Round 1 could have seen this; it is raised now because it is a defect in the answer's revised line.
Critique: the tempting fix is to add "grok and cursor have the same trailing `/`" to Siblings and stop. That leaves two more known-broken spend readers with no id, which the checklist forbids.
Consequences: the cheapest code fix, stripping once at the top of `span` (`cwd = string.gsub(cwd, "/$", "")` before any key), fixes all three folders in one line and keeps `kimi` (already stripped through `samePath`, line 129) unchanged; but it changes grok and cursor reads, which the Problem (Claude only) does not name, so it is a scope question like round 1's F2, needing a grok case (session only under `%2Fa%2Fb`) and a cursor case (session only under `a-b`) with a row each. Cursor's own naming of `.` (`…-pickman-worktree-captu-075c893` shows it drops the dot and shortens the name) is a separate rule the strip does not fix.
Recommendation: name the grok folder (line 152) and `cursorKey` (line 173) under Siblings as having the same trailing-`/` mistake, with the evidence above, and add them to open bullet 2 so the human rules on all three siblings at once: fix the trailing `/` in d0328 (strip once at the top of `span`, a grok case and a cursor case, two rows), or capture one defect for them and name its id in Siblings. Do not pin cursor's dot rule in either option without evidence of it.
Lesson: zz-arch/compare-canonical-spellings
Erred: z-design
Upstream: zz-review

### F2 [low] Open bullet 1 calls the two-character rule "the captured Solution" without telling the human that the capture itself asked for "the real folder name" and that the narrowing came from the idea step
Where: d0328.md:115 ("The captured Solution names only `/` and `.`" … "keep the rule as captured"); design-refute-001.md:3.
Evidence: the capture commit 3cadd2cef, the version `./zn capture` prints (z-design SKILL.md:10), has no Solution section; its Problem says "a spec seeds a session under the real folder name only" and says nothing about `.` or any other character. The Solution "maps both `/` and `.`" and the Non-goal clause "no character other than `/` and `.` is mapped" were written by the idea step in 3290615a3 (`tracker: idea batch 2 … challenged`), answering idea-review-001 F1, which asked only for `.` to be added. No `Scope decision` or `Decided with the user` line records the human choosing the fence. z-ticket SKILL.md:20 does make the idea's outcomes scope, so "as captured" is defensible, but the human is asked to choose between "as captured" and "widen" without being shown that the original capture's words ("the real folder name", still in today's Solution at d0328.md:27) point at the wider rule. The refute also labels F1 and F2 "fixed" when both were escalated.
Critique: the bullet's two options and their costs are right; only its premise is one-sided.
Consequences: none beyond the wording.
Recommendation: reword bullet 1 to quote both texts with their commits: the capture (3cadd2cef) asked for the session "under the real folder name"; the idea step (3290615a3) added the Non-goal limiting the mapping to `/` and `.`, with no ruling by the human. Keep both options as they are.
Erred: z-design
Upstream: none

### F3 [low] Open bullet 2's option "fix it in d0328" leaves out what it costs: a `running` case needs a signature change or a shared function
Where: d0328.md:116; sessionread.luau:206-207; d0328.md:30 ("no change to any signature").
Evidence: `running()` takes no argument and reads `process.cwd` (line 207), which a spec cannot set in-process, so "a `running` case and a row added" cannot be written without either giving `running` a cwd parameter (against Design line 30) or moving the key into one function that `span`, `running` and a spec all call. Round 1 F2's Consequences said this; the bullet does not. `running` today also reads only the loose spelling (line 216), so the human should know whether the fix keeps a fallback to it the way `claudeDirs` does (lines 263-265).
Critique: without the cost the "fix here" option looks like a one-line change.
Consequences: none beyond the wording.
Recommendation: add to the "fix here" option: it needs a shared key function (or a cwd parameter on `running`), a case on that function, and a row; and state whether `running` keeps the loose spelling as a fallback.
Erred: z-design
Upstream: none

### F4 [low] Two places still describe one acceptance spec, and the round-1 hard-coded mutant is not in the table
Where: d0328.md:67 ("New spec: `…/spend-session-cwd.spec.luau`"), d0328.md:109 ("The acceptance spec moves"), Rules and mutants d0328.md:92, E2 d0328.md:71.
Evidence: the issue now has two specs (check.sh:12-13), but line 67 names only `spend-session-cwd.spec.luau` and step 3 says "the acceptance spec". Round 1 F3 named the `%.worktree` → `-worktree` hard-code as a plausible mutant; I ran it on the prototype and AC2 kills it (AC1 passes), but neither row 4 nor E2 records it.
Critique: an executor reading line 67 alone would not know `spend-session-dot.spec.luau` belongs to the issue.
Consequences: none.
Recommendation: name both specs on line 67 and in step 3; add the hard-code to row 4's mutant cell (or its own `run` row) and to E2.
Erred: z-design
Upstream: none

### F5 [low] The harvest's one-off reasons for round 1 F1 and F2 restate the escalation, not the mistake, and F2's repeated lesson is not recorded
Where: harvest.md:1-2.
Evidence: round 1 F1's mistake was that AC2 pinned `-a-b_c--worktree-x`, a spelling Claude Code never writes, against both the on-disk folders and the repo's own `claudeDirs` comment (sessionread.luau:259-260); the harvest reason is "widening the rule … is a user scope call", which is the answer, not what went wrong. Round 1 F2 carried `Lesson: zz-arch/compare-canonical-spellings` (whose check names "a cwd turned into a folder name … trailing `/` included … the same way in every reader"); z-design SKILL.md:70 says a finding that repeats a lesson sharpens that lesson's check, and the harvest says "one-off" instead. Both are mistakes another raft could make.
Critique: a one-off line that describes the answer teaches nothing.
Consequences: the lesson for F1 must be filed under `z-design` or `z-ticket` with `when: design` or `both`; F2's tie to a `zz-arch` lesson goes through a note entry, since an entry's lessons must sit under its `erred` or `upstream` skill.
Recommendation: F1: name a z-design lesson (new, or a source on an existing one) such as "before a spec pins an external tool's naming, compare it with that tool's real folders and with the repo's existing reader of them". F2: keep or replace the entry, and add `- note design-review-001 F2 sibling reader made canonical differently (erred zz-arch): zz-arch/compare-canonical-spellings`, sharpening that lesson's check to name every folder one function builds from one input. Candidate lessons are the lead's to write.
Erred: z-design
Upstream: none

## Categories with nothing found
- Rules and mutants: every `run` row reproduced; the `reasoned` row 2 (`/` kept) is killed by both specs (a key with `/` names a nested path that is never seeded). No other plausible mutant survives both specs except the wider `[^%w%-]` rule, which is the human's open choice.
- Acceptance criteria: AC1 and AC2 are both Checked, each by its own spec file whose case name matches the Test plan (d0328.md:83-84) and the check labels.
- Regressions / Overrides: `Overrides: none` holds. `work.spec.luau` is green on the prototype; f0399 `land.spec.luau:755` seeds a folder that `sessionread.id` reads through `claudeDirs`, not `span`; `c0322/wiring.spec.luau` greps `main.luau` text the change does not touch.
- Repository safety: both specs write only under `{process.cwd}/.cache/d0328-spend-session*/`, set `HOME` in-process and restore it before the assert (the call is in a `pcall`), start no process and run no git; `check.sh` runs only `tests/run`.
- Architecture: `span` stays an adapter; no new require or edge.
- Bounded commands: experiments ran through the spec runner; no step asks for an unbounded command.
- Executability: apart from F4, the one-line change and both specs are concrete.

Not settled: F1 is medium.

Verdict: changes
