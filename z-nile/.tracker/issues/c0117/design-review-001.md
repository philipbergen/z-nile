# Review 001: c0117 (design mode)
Inputs: `prep-c0117` at c74b7da (`z-nile/.tracker/issues/c0117/{c0117.md,check.sh,acceptance/*}`); prototype `.worktree/proto-c0117` at bb16d0b on 4b71031 (`./zn check c0117` rerun there: 9/9); capture `./zn capture c0117` (fb7fd80, no marker) and main's history of the item (37ddf28, fb7fd80, ab750c0, da8b9ac, 4c2b747); the programme review `programme-review/c0117.md`; `./zn lessons --when design --full`, `./zn lessons --skill review --full`. Bypass attempts were run in a scratch fixture under the session scratchpad: a bare origin, a clone, and the prototype's `z-nile/bin/{git,gh}` first on PATH with `ZN_REAL_GIT=/usr/bin/git` and a fake real `gh`. No real CLI, no network.

Scope (item 11): the capture is confirmed. The title, Problem and the three Solution bullets are as captured, and every addition is a dated `Decided with the user` block or a labelled prep bullet. Every captured outcome has a Design and a Checked criterion, except that "stops at the cap" holds only nominally for two runtimes (F6).

Guesses: G1, G2, G3, G6, G7, G9, G11, G12, G13 and G14 are reasonable. G4 fits the decision that the wrapper refuses "any merge the dispatcher didn't authorise" (that wording implies the dispatcher authorises some), but see F7. G5 contradicts a decision (F3). G8 is undermined by F10, and G10 by F8.

### F1 [high] The git wrapper lets most ways of pushing to `main` through: 12 of 19 forms tried in a fixture moved `main` to a commit that adds code
Where: §7 "git push"; `z-nile/bin/git` (prototype); `wrapper.decideGit`, `gitCommand`, `GIT_VALUE`; `wrap.luau` `ctx.changed` and `ctx.allowed`; AC4; wrapper.spec.
Evidence: on branch `feat`, one commit adds `code.lua`. Each command ran through the shim, and origin's `main` was reset to the base before each one.
- Refused (correct): `push origin HEAD:main`, `HEAD:refs/heads/main`, `--force-with-lease`, `env git push`, `-C . push`, `git push` with upstream `origin/main`.
- **Moved main**:
  - `git --git-dir .git push origin HEAD:main` and `git --work-tree . push …`. `gitCommand` steps over the option but not its value, so it takes `.git` as the command.
  - `git -c alias.p=push p origin HEAD:main` and `git --config-env=alias.p=X p …`. No argument equals `push`, so the shim runs the real git.
  - `git push origin HEAD:heads/main`. git's DWIM maps this to `refs/heads/main`, and `MAIN` doesn't list it.
  - `git push origin 'refs/heads/feat*:refs/heads/main*'`, a wildcard refspec.
  - `git push origin :` and `git -c push.default=matching push origin`, with a local `main` at the code commit.
  - `git -c remote.origin.push=refs/heads/feat:refs/heads/main push origin`. There is no refspec, so the wrapper assumes the upstream or the current branch.
  - `git send-pack ../origin.git feat:main`.
  - `git update-ref refs/remotes/origin/main HEAD && git push origin HEAD:main`. `changed` diffs from the merge base with the *local* tracking ref, which the agent just rewrote, so the diff is empty. `allowed` reads the registry from that same ref, so the agent can widen the roots the same way.
  - `$ZN_REAL_GIT push origin HEAD:main`. The design accepts this one ("an absolute path"), but the real path is handed to the agent in its environment.

The prototype's `./zn check c0117` passes 9/9 with all of these open, so AC4 is passed by a wrong implementation. Trusting the local `refs/remotes/origin/main` is the defect the lesson below names: the agent can write that ref.
Critique: the tempting fix is to add each spelling to the parser (`--git-dir` to `GIT_VALUE`, `heads/main` to `MAIN`). git has more spellings than a hand parser will ever list: aliases, config refspecs, `push.default`, wildcards, plumbing.
Consequences: deciding from git's own resolution needs the remote, which means a network round trip on each push and a fixture origin in specs. Routing more invocations to Lune costs about 0.1 s each.
Recommendation:
- **What the push would do.** Decide from git itself. Run `git push --dry-run --porcelain <same global options and args>` with the real git and the same environment, and read every `<src>:<dst>` line. `send-pack` and `http-push` get the same treatment.
- **What the shim routes.** The shim sends to `wrap` every invocation that contains `push`, `send-pack` or `http-push`, any `-c`/`--config-env` option, or a first word that `git config --get alias.<word>` resolves.
- **The base.** "What would land on main" is diffed from a private, freshly fetched copy of origin's `main` (`git fetch <remote> +refs/heads/main:refs/zn-wrap/main`, then the diff), and the registry is read from that copy. Never from `refs/remotes/<remote>/main`.
- **Spec cases.** The shim runs for real in the fixture, one case per form above, each refused. Rows and mutants: "a destination is read from git's dry run, not parsed" and "the base is a fresh fetch, not the tracking ref".
Lesson: zz-arch/guards-trust-only-origin

### F2 [high] The gh wrapper passes merges and direct writes to `main`, and the authorisation it checks is a file the agent can write
Where: §7 "gh pr merge", "gh api"; `z-nile/bin/gh`; `wrapper.decideGh`; `$ZN_DISPATCH_HOME/authorised/<n>`.
Evidence (the shim with a fake real `gh`):
- **Passed to the real gh**:
  - `gh -R o/r pr merge 5`. The shim only checks `$1 == pr && $2 == merge`, and the real gh accepts `-R` before `pr` (`gh -R o/r pr merge --help` works).
  - `gh api graphql -f query='mutation{mergePullRequest(...)}'`. The endpoint `graphql` contains none of the three words.
  - `gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=… -F force=true`, which moves `main` directly.
  - `gh api -X PUT repos/o/r/contents/src/x.lua …`, which commits code straight to the default branch.
  - `gh api -XPUT repos/o/r/pulls/5/merge`. The attached form of `-X` is not parsed, so the call isn't seen as a write.
  - `gh api -X PATCH repos/o/r -f default_branch=feat`.
- **Not tried, but the same shape**: a gh alias (`gh alias set m 'pr merge'`, then `gh m 5`) goes to the real gh, because only the literal first words are checked.
- **Self-authorisation**: `touch $ZN_DISPATCH_HOME/authorised/5 && gh pr merge 5` passed. The environment names the folder, it lies in the main checkout that a `bypassPermissions` agent can write, and the refusal message tells the agent what is missing.

Critique: the tempting fix is to add `graphql` and `/git/refs` to `API_WRITES`. A deny-list of endpoints can't keep up with GitHub's API.
Consequences: an allow-list must cover every write the skills legitimately make (PR comments, `gh pr create`, `gh pr ready`). That list is exhaustive, so it needs a spec over the skills' `gh` lines.
Recommendation:
- **No merges by the agent.** The headless rule already says the agent never merges, so under `ZN_DISPATCH=1` the wrapper refuses `pr merge` wherever it appears (after skipping gh's global flags `-R`/`--repo`/`--hostname`), resolving aliases first (`gh alias list`), and refuses `alias set`/`alias import`.
- **The dispatcher's own merge.** The dispatcher's gate merge calls the real `gh` directly. It already checked green and mergeable in `dispatch.next`. With no agent-side merge left, `authorised/` goes away and the decision's "merge the dispatcher didn't authorise" is met by construction.
- **`gh api`.** Reads only, plus an allow-list of the write endpoints the skills use (issue and PR comments). Every other write is refused, GraphQL mutations included.
- **Spec cases.** One per form above, plus a case that walks the skills' `gh` invocations against the allow-list.
Lesson: zz-arch/guards-trust-only-origin

### F3 [high] G5 contradicts the decision "main gets branch protection (a PR and green CI required)": the admin bypass covers the only identity that acts, so for an unattended agent nothing requires a PR or green CI
Where: §8 (`bypass_actors: RepositoryRole 5, bypass_mode always`), G5, E9; §4 (`--permission-mode bypassPermissions`, `--always-approve`, `--force --sandbox disabled`); §7 "The wrapper is bypassable".
Evidence:
- Every dispatched agent runs with the user's credentials (`~/.config/gh`, the git credential helper), and the user is the repository admin. Under G5's ruleset that identity bypasses "always", so a push or merge by the agent is never stopped server-side. §8 says so itself ("The bypass also covers an agent that runs with the user's token").
- The agent auto-approves every tool call and gets `ZN_REAL_GIT` and `ZN_REAL_GH` in its environment.
- Its worktree is only its cwd. It can write the main checkout (AGENTS.md forbids that), other worktrees, `.cache/dispatch/*` (F2, F4) and `$HOME`.

To answer the brief plainly: the wrapper plus worktree isolation is a guard against honest mistakes, not a boundary. An agent that works around a refusal, as models commonly do ("let me use the absolute path", graphql), meets nothing, and F1 and F2 show that even unintended forms get through. The user chose "Branch protection + wrapper" for unattended steps on the premise that protection requires a PR and green CI. G5 keeps the name and drops that premise.
Critique: the tempting fix is to set `bypass_mode: "pull_request"`. That breaks `publish` and `land`, which push tracker state straight to `main`.
Consequences: any real boundary changes the identity or the OS context the agent runs in. That touches publish and land (tracker pushes), credentials and the gate's jail (macOS can't nest sandboxes: programme review F5).
Recommendation: escalate to the user, with the options and their costs:
- (a) Keep G5 and record a decision line that an unattended agent can push to or merge into `main` if it tries. This costs nothing.
- (b) Run dispatched steps with a credential that has no bypass (a fine-grained token, or a GitHub App installation token, set as `GH_TOKEN` plus a git credential helper in the step's environment). Tracker pushes during a step then fail, so `publish` and `land` move to the dispatcher after the step, or to a bypass actor whose key the agent can't read. That second part is only real with an OS-level separation, such as a different macOS user. The cost: moderate code, plus a credential setup by the user.
- (c) An OS sandbox per step that denies writes outside the step's worktree and `.cache` and limits the network to the model API and GitHub. It collides with the gate's jail, which would need a redesign.

Whatever the user picks, add a **post-step tripwire** in the dispatcher. It is cheap, and the agent can't bypass it, because it runs after the step's process group is gone:
- compare `origin/main` before and after the step: any commit that touches a non-tracker path, or a PR merged that the dispatcher didn't merge, stops the chain with its own exit code and a report;
- the same for the main checkout's HEAD and status, and for another worktree's branch moving.

Spec: a fake CLI that runs `$ZN_REAL_GIT push origin HEAD:main` with a code commit. The chain stops at the tripwire, and the step's spend is still recorded.

### F4 [high] Process control: the step outlives the dispatcher with no cap, and `stop` kills `-<pgid>` from stale state with no check that the group is still this run's
Where: §4 "The runner"; `runner.run`, `runner.killGroup`; `dispatcher.main` `stop`; `state.json` `pgid`; c0118's stop button (§12).
Evidence:
- **(a) The step outlives the dispatcher.** The launcher's `setpgrp` takes the CLI out of the terminal's foreground group, so Ctrl-C, a closed terminal or a crash of `./zn dispatch` leaves the agent running, unattended, with `bypassPermissions` and nothing enforcing the cap, the stall or the stop. Verified with Lune 0.10.5: `process.create("perl", {"-e", "setpgrp(0,0); exec('sleep','47')"})`, then `kill -INT` of the Lune process; the `sleep` survives.
- **(b) `stop` trusts stale state.** After such a death `state.json` keeps `pgid` and `outcome = "running"`. A later `./zn dispatch stop <id>`, or the board's button, runs `kill -TERM -- -<pgid>` and then `-KILL` on whatever group holds that number by then (pid reuse). Nothing checks the leader's identity or start time, or that the number is above 1. A `pgid` of 1, written by a confused agent (the file is in its reach) or by corruption, makes `kill -TERM -- -1` signal every process the user owns.
- **(c) No lock.** Two `./zn dispatch` on one id (a terminal, and the board's retry) start two CLIs in one worktree, and each overwrites the other's `state.json`, pid file and stop marker.

No spec covers any of the three.
Critique: the tempting fix is to clear `pgid` more often. That doesn't help when the dispatcher is gone.
Consequences: a supervisor that outlives the dispatcher has to notice the dispatcher's death. A lock has to tell a live holder from a dead one, so it needs the holder's pid and start time, which brings pid reuse back for the lock too.
Recommendation:
- **A lifeline.** Make the perl launcher a supervisor. It forks the CLI into the new group and keeps a pipe from the dispatcher open as its stdin. On EOF (the dispatcher died), it kills the group TERM, then KILL.
- **A checked kill.** Record the leader's pid, its start time (`ps -o lstart= -p <pid>`) and its command in `state.json`. `stop` signals the group only when all three still match, refuses any `pgid` ≤ 1 or non-integer, and otherwise marks the run `lost` and kills nothing.
- **A run lock.** Add `.cache/dispatch/<id>/lock` with the dispatcher's pid and start time. A second dispatch on a live lock is refused. A dead holder is reported as `lost`, and only `retry` takes the lock over.
- **Spec cases:**
  - kill the dispatcher mid-step, and no fake process is left;
  - `stop` on a stale state whose pgid now names a live, unrelated group (a `sleep` the spec starts in its own group) leaves it alive;
  - a pgid of 1 is refused;
  - a second dispatch on a running id is refused.

### F5 [high] A dispatched review started from a dispatched author (the headless rule's required path) hangs on every git call and shares the author's run state; no spec covers it, so programme review F9 is not fully answered
Where: §5 environment (`ZN_REAL_GIT` = `resolveBin("git", basePath)`, `basePath = process.env.PATH`); §9 headless section ("start every review with `./zn dispatch zz-review …`"); `dispatcher.modelStep`, `stateDir = dirOf(id)`; `runner.run` (removes and writes `<stateDir>/pid` and `stop`).
Evidence:
- **The hang.** The author's PATH already starts with `<main>/z-nile/bin`, so the nested dispatcher's `command -v git` resolves to the shim, and `ZN_REAL_GIT` points at the shim itself. In the shim, a non-push call does `exec "$real"`, which is itself, forever. Verified: the shim with `PATH=<bin>:…` and `ZN_REAL_GIT=$(command -v git)` hangs on `git status` (the probe had to be killed). A push recurses through Lune.
- **Shared state.** The nested review uses the author's `.cache/dispatch/<id>/`. It deletes the author's pid file and stop marker, writes its own pid, and sets `state.json`'s pgid to its own and then to nil, so `stop <id>` can no longer find the author's group by pgid. The author's final `save` overwrites the history with its in-memory copy.

dispatch-cli.spec has no nested case: programme review F9 asked for "a design chain with fake grok (author) and fake claude (reviewer) [that] produces `design-review-001.md` from the claude fake and a spend row with the reviewer's model". AC6 passes regardless.
Critique: the tempting fix is to reuse an inherited `ZN_REAL_GIT`. That trusts a variable the agent can set (export it to the shim, or to anything else).
Consequences: a nested step needs its own run-state slot, `status`, `stop` and c0118 must show both, and `retry` must know which one it is retrying.
Recommendation:
- **The real binaries.** Resolve them on a PATH with every `z-nile/bin` entry removed (compare physical paths), never from an inherited variable.
- **Its own state.** Give a nested step its own folder (`.cache/dispatch/<id>/zz-review-<mode>-<n>/`) with its own pid, stop and state, and name it in the parent's state (`children`). `stop <id>` stops both, and c0118's interface names the field.
- **Spec.** Programme review F9's case: a fake `grok` author runs `./zn dispatch zz-review <id> --mode design`, and a fake `claude` reviewer runs `git status` and writes `design-review-001.md`. The review file appears, the row carries the reviewer's model, and the author's state and pid are intact. Mutant: "real git resolved on the inherited PATH".

### F6 [high] For `cursor-cli` and `cursor-app` the cap is an estimate that undercounts by about the number of model calls, so the captured "stops at the cap" holds in name only
Where: §4 table (`cursor-cli`: "an estimate, a token per four characters streamed"); `agentFeed` (`acc.live += ceil(#line/4)`); E2 (agent: 15,155 input against 28 output); Problem ("stops at the cap").
Evidence: the count the cap uses is input + cache writes + output. agent re-sends its context on every model call, and the streamed lines carry only the new text of each turn, so the estimate grows with the transcript, while the real count grows with the transcript times the number of calls. In the one probe, the input was 15,155 tokens and the output 28. A one-line answer streams a few hundred characters, an estimate of about 100 against 15,183. A 100-call z-run on `agent` with G1's 12M cap would have to spend on the order of 100 times the cap before the estimate reaches it. No decision line accepts that, and AC6's cap case uses only the claude and grok fakes.
Critique: the tempting fix is to multiply by a constant. The ratio depends on the length of the session.
Consequences: a better estimate overcounts in some sessions, which kills early. That is safe for spend but kills real work, so the error's direction must be chosen and stated.
Recommendation: estimate each model call's input as the cumulative size of the transcript so far, plus the prompt, plus a measured allowance for the system prompt (E2's first-call input), and add that to the output at every assistant turn. Calibrate against the final `usage` of one multi-turn probe in Phase 1, and record the ratio. Spec: on a recorded multi-turn agent stream, the running estimate is ≥ 0.8 × the final count, with a mutant that drops the cumulative term. If the user prefers otherwise, escalate to the user: (a) accept the undercount as a decision line, (b) the cumulative estimate (this recommendation), (c) give agent runtimes a turn or time cap beside `max_tokens`.

### F7 [high] `auto_merge` is read from the root file only, and a failure to read it turns both merge gates on
Where: §1 "Which walk" ("`order` and the settings come from the raft's own walk"); §6.8; `dispatcher.facts`: `local autoMerge = table.clone(models.GATES)` and `pcall(models.resolve, models.walk(".", "."), "z-design")`; `models.resolve` (`settings.autoMerge` defaults to `models.GATES`).
Evidence:
- **Ignored setting.** An issue folder or project home with `[dispatch] auto_merge = []` is ignored, because `facts` walks only to `.`, so the dispatcher still merges that item's prep and rafting PRs.
- **Fail open.** If the root file fails to parse or names no `z-design`, the `pcall` fails and `autoMerge` stays `{prep, raft}`.
- **Default on.** A tree whose files never set `auto_merge` also merges.

A guard on a merge whose every failure leads to "merge" is the defect the lesson names. No spec reaches it: `dispatch.spec` passes `autoMerge` in as a fact, and in dispatch-cli `onGitHub` is false, so no gate is ever reached through `facts`.
Critique: the tempting fix is to walk to the item's folder. That still leaves the fail-open fallback and the default.
Consequences: making the default "no auto-merge" changes G4's effect unless the root file sets it, and the root file does (`auto_merge = ["prep", "raft"]`). A test seam for `gh pr view` is needed so that gates can be exercised in dispatch-cli.
Recommendation:
- **The walk.** Read the settings from the item's own walk (a raft's own folder), as §1 says.
- **Errors and defaults.** A resolve error, or an unset `auto_merge`, means no auto-merge: stop 4 and name the reason.
- **A seam.** Add `ctx.prView(branch)` so that `facts` can run against a fake gh.
- **Spec cases:** an issue-folder `auto_merge = []` with a green PR stops at the gate; a broken root file stops at the gate; mutants for both.
Lesson: zz-arch/guard-no-is-explicit

### F8 [medium] A stall becomes "quota" on the model's own words, and a long tool run is killed as a stall
Where: §4 "Quota"; `runner.run` (at a stall: `mentions(acc.lastText .. stderrTail, WAITING) or mentions(…, QUOTA)`); `claudeFeed`/`agentFeed` (`lastText` = the assistant's text); G10.
Evidence:
- **The model's words count.** `lastText` is the assistant's prose. Suppose a step's last words were "I'll run the gate and try again" or "waiting for the full gate" (WAITING has "try again" and "waiting for"), or anything about rate limits or quota (this repo's own adapters and skills discuss both), and then a Bash call runs quietly past `stall_seconds`. That step is classified `quota`, and the dispatcher reruns the step on the next CLI in the same half-edited worktree.
- **Long tools are killed.** claude streams nothing while a tool runs. `z-nile/check.sh --full` took 137 to 162 s here, and z-run's full gate plus checks can pass 300 s, at which point a healthy run is killed as `stalled`.

G10 says plainly that "a step that prints nothing … is killed whatever it was doing", but neither case is named, and the misclassification has no spec.
Recommendation:
- **CLI text only.** Match WAITING and QUOTA only in what the CLI itself emits (stderr, `system`/`error`/`rate_limit_event` lines, error `result` text), never in assistant content.
- **Open tool calls.** While a tool call is open (a `tool_use` or `tool_call` line with no result yet), the stall timer gives way to a tool ceiling (a `[dispatch]` setting, for example 900 s).
- **Spec cases:** assistant text "try again" followed by a stall is `stalled`, not quota; an open tool call that stays quiet past `stall_seconds` is not killed before the ceiling.
- Record the refinement in G10.

### F9 [medium] The headless instructions can't all be followed where they run
Where: §9 headless section ("Never merge a pull request and never push to `main`"); §5 ("z-ticket's id is the one issue on `origin/main` that was not there before"); G4; z-run Phase 2B, 7 ("Stream implementers and stream reviewers run on Sonnet", unchanged); JC1.
Evidence:
- **(a) z-ticket can't land.** z-ticket must land its capture on `main` (`./zn land`, make-issue) for the chain to find the issue. The headless section, word for word in z-ticket, says never push to `main`, and it doesn't say whether `./zn land`, `publish` or `status` count. An agent that obeys it leaves the issue unlanded, and the step fails "z-ticket made 0 issues". make-issue's "ask whether to land" isn't lifted in the skill text either: G4 lives only in the design.
- **(b) No Sonnet under grok.** A z-run on `grok` has no Sonnet subagent for its stream reviewers.
- **(c) JC1 can't catch either.** Its rubric covers only z-design.

Recommendation:
- The headless section says exactly: "`./zn land`, `publish`, `status` and `spend` push tracker state to `main` and are allowed; never `git push` to `main` and never merge". z-ticket's copy adds "under the dispatcher, land the capture without asking (the user started the dispatcher)".
- Define the stream-review model under the dispatcher, for example "the author CLI's own subagent at the model `.models.toml` names for `zz-review` in a `stream` mode". Escalate to the user if a new key is unwelcome.
- Widen JC1's rubric to (e) z-ticket's landing and (f) a grok z-run's stream reviews.
Lesson: z-design/instructions-runnable-where-they-run

### F10 [medium] The sequestered adapters spec pins the unproven command lines whole, so E7's documented fallback turns AC3 red
Where: E6 to E8, G8; adapters.spec lines 67–69 (claude-cloud), 89–99 (`grok agent … headless`, stdin), 119 (`agent worker --model M --workspace /w/wt`).
Evidence: E7's fallback is "`grok agent … stdio` …, recorded as a deviation". `toEqual` pins `headless`, and the spec is sequestered, so the executor can't follow the documented fallback without a red AC3. E8 already doubts that `agent worker` takes a prompt at all.
Recommendation: run E6 to E8 in prep with the user's consent (one tiny prompt each, as E1 did) before sequestering, and pin what they show. Otherwise make each fallback an escalation, not a deviation, and say so in E6 to E8.
Lesson: z-design/no-check-red-between-steps

### F11 [medium] AC9 runs the new `./zn dispatch … --dry-run` against the real checkout, and nothing pins that a dry run starts and writes nothing
Where: check.sh AC9 (`./zn dispatch z-design c0117 --dry-run`); Rules and mutants (no row for `--dry-run`).
Evidence: suppose an implementation ignores `--dry-run` on a one-step run. It would run `./zn worktree prep-models-and-dispatcher` from the real main checkout (`ctx.mainRoot()`) and write the real `.cache/dispatch/c0117/state.json` (the user's live run state for this item) before `checking()` refuses the CLI. The fence and the refusal limit the damage, but the lesson asks that a new command's spec runs in a copy.
Recommendation: check AC9's "the root file resolves z-design" with a pure `models.resolve(models.walk(…))` call, or in a fixture with the real `.models.toml` copied in. Add a dispatch-cli case and mutant: `--dry-run` makes no worktree, writes no `state.json` and starts no fake.
Lesson: zz-test/new-commands-run-in-a-copy

### F12 [medium] Rules and mutants is missing rows for behavioural rules in the Design
Where: Rules and mutants.
Evidence: these rules have no row and no mutant:
- refusing `--all`, `--mirror`, `--branches` and deleting `main` (wrapper.spec case 111 exists);
- refusing `gh api` writes (case 133 exists);
- a shim exits 2 without `ZN_REAL_*`;
- a missing binary is a failure, not quota (G11);
- `--dry-run` starts nothing (F11);
- rows for non-backlog items go to `pending.json` and are flushed as `deliver` after the merge;
- a review's row note is the review file's name;
- the settings come from the item's walk (F7);
- z-ticket walks to the project's home (G12);
- at most 30 actions;
- `stop`'s marker ends a running step (M35 covers its outcome, not the marker as such).

Recommendation: add a row per rule with its case, and run the new mutants on the prototype.

### F13 [low] `prototype.patch`, which the Design names, is not in the item folder
Where: Design intro ("`prototype.patch` beside this document"); `z-nile/.tracker/issues/c0117/` holds only `acceptance/`, `c0117.md`, `check.sh` and `spend.md`.
Recommendation: commit it, or drop the sentence (c0116 carries one).

### F14 [low] Programme review E6 (does the gate's jail engage under a headless agent) is unanswered, though the document says the programme's E1 to E8 are
Where: "Programme review … 'What prep must settle' E1 to E8"; this document's E6 to E8 are different experiments (claude-cloud, grok-bot, cursor-app).
Evidence: the programme's E6 asked whether, in a headless claude run, `check.sh --affected` engages `sandbox-exec` rather than refusing as "already inside a sandbox". Only agent's `--sandbox disabled` is pinned (M25). claude and grok "run without their sandboxes by default" is unprobed, and a user's claude settings can turn claude's sandbox on.
Recommendation: map the programme's experiment numbers explicitly. Make claude's sandbox state explicit in its argv (for example a `--settings` value that disables the sandbox) and pin it, or run that probe in Phase 1.

### F15 [low] The refusal case relies on the runner's host markers
Where: dispatch-cli "inside a check, refuses a CLI whose real path is not under .cache".
Evidence: `checking()` reads `PICKMAN_FENCE_SPECS` and `PICKMAN_FENCE_REAL_GIT`, inherited from `tests/run`. The case doesn't set either.
Recommendation: set `PICKMAN_FENCE_SPECS=1` in that case's environment.
Lesson: zz-test/specs-set-host-markers-explicitly

Candidate lessons (for the lead):
- A wrapper decides from the tool's own resolution, not a parser of its arguments. For example `git push --dry-run --porcelain` gives the destinations; a hand parser misses aliases, config refspecs, wildcards and plumbing. Check: can an alias, a config key or a different spelling of the same command reach the action the guard refuses?
- A process the tool starts in its own group outlives the tool, so it needs a lifeline. A kill by a stored pid checks the process's identity first. Check: what happens to the child when the parent dies, and what does a stored pid name after reuse?

Verdict: changes
