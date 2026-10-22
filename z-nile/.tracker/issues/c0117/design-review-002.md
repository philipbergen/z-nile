# Review 002: c0117 (design mode)
Inputs: `prep-c0117` at 23d0978 (`z-nile/.tracker/issues/c0117/{c0117.md,check.sh,harvest.md,acceptance/*}`, `design-review-001.md`, `design-refute-001.md`); prototype `.worktree/proto-c0117` at da468f0 on 04aa603, read only; `./zn capture c0117` (fb7fd80, no marker); `./zn lessons --when design --full`; the new lessons `architecture/{guards-decide-from-the-tools-resolution,children-need-a-lifeline}`. Attacks ran in a scratch clone of the prototype under the session scratchpad (origin repointed to a path that doesn't exist), through `lune run tests/run` (the jail), with one extra fake mode (`script`: the fake CLI runs `$FAKE_DIR/script.sh` inside a dispatched step) and a spec of six cases in a `.cache/c0117-attack` fixture. No real CLI, no network, no real origin.
Dropped from review-001: F1, F2, F5, F7, F8, F9, F10, F11, F12, F13, F14, F15 (fixed: wrapper.spec reruns 10/10 in the clone, and a `pushurl` decoy I added is refused, because the wrapper fetches the dry run's `To` URL); F3 and F6 (decided by the user; their mechanisms are judged below); F4 (fixed, apart from one window: F10).

Scope (item 11): the capture is confirmed. The two new `Decided with the user (2026-10-21)` blocks are dated, and the Problem is unchanged. "Stops at the cap" for the cursor runtimes rests on `max_calls`, which fails open (F8).

Guesses: G15 is reasonable: stream reviews are reviews, so the user's review-model rule covers them, and the extra cost is stated. G16's 200 is a reasonable first guess. Its second half ("a call with no `model_call_id` is not counted") is not: it is what makes the cap fail open (F8). G17 is reasonable. G18 is reasonable as a policy, but the "tracker state" it allows is too wide (F2), and its window misses everything after the step (F4). G19's flock identity is reasonable. Its 120 s contradicts §5's 600 s (F12).

### F1 [high] The broker's tracker-only check reads `git diff --name-only`, which hides a rename's source. A step deleted a non-tracker file from `main` through the broker, and the tripwire stayed quiet.
Where: §5 "The publish broker"; `dispatcher.brokerPush` → `namesOf` (`git diff --name-only mb sha`) and `stray`; `trackerPrefixes` (`"z-nile/next"` with no trailing slash); `wrap.luau` (the same `diff --name-only`, the same prefix); `dispatcher.tripwire` (`if not pushed[sha]`); Rules and mutants row "the broker pushes tracker state only | none | … reasoned".
Evidence (attack spec, cases A and C; the step exits 0 and the tripwire is quiet in both):
- **A.** The step runs `git mv src/guard.lua tracker/guard.lua; git commit` and writes a broker request for that commit. Answer: `{"ok":true,"message":"pushed"}`. Origin's `main` no longer has `src/guard.lua`, and the outcome is `ok`. `git diff --name-only` prints only `tracker/guard.lua`; `git diff-tree` prints both paths.
- **C.** The step adds `z-nile/nextgen/evil.luau`, and the broker pushes it: `string.sub(p, 1, #"z-nile/next") == "z-nile/next"`.
- **The tripwire is no backstop.** It skips every sha in `st.pushed`, so whatever the broker misjudges is exempt by construction. The reasoned row says "the tripwire would then trip, since `state.pushed` exempts the commit". That is backwards: because of the exemption, it never trips. No case asks the broker to push anything but tracker state.
- **Not tried, but the same blind spot:** symlinks (mode 120000) and gitlinks (160000) under a root, and `.gitattributes` under a root. The check sees names, never modes.

Critique: the tempting fix is `--no-renames` here and a `/` after `z-nile/next`. Round 1 found the same defect class in the wrapper's own path judgement (F1). There are now three copies of "is this tracker state": the wrapper, the broker and the tripwire. Each spells it differently (`diff --name-only` in two, `diff-tree -m` in one), and patching each spelling is the parser problem again.
Consequences: one shared function changes the wrapper's and the tripwire's behaviour too. The wrapper's and the broker's outputs must then agree, which needs a spec.
Recommendation: question the mechanism. Write one pure-plus-git function, `trackerState(root, base, sha, registry) -> (ok, why)`, and use it in all three places.
- It reads `git diff-tree -r --no-renames --raw base sha` (both sides of every change, and the modes).
- It refuses any path that isn't under `<root>/` (with the slash) or equal to `z-nile/next`.
- It refuses any mode except 100644 and 100755, and refuses `.gitattributes` and `.gitmodules` anywhere.
- The tripwire re-checks broker-pushed commits with it too, instead of exempting them.
- Rows and mutants:
  - a rename out of a root is refused (mutant: `--name-only`);
  - a `z-nile/next*` sibling is refused (mutant: prefix without the slash);
  - a symlink under a root is refused;
  - the broker refuses a code commit, and the tripwire trips on a broker-pushed commit the check would refuse (mutant: the exemption).
Lesson: testing/plain-find-for-literals, ticket-prep/spec-design-correspondence

### F2 [high] The broker pushes edits of sequestered `check.sh` files and acceptance specs to `main`, because they lie under a tracker root. An agent can weaken its own acceptance checks unreviewed.
Where: §5 "The publish broker"; §6 G18 ("any commit on `main` that only changes tracker state"); the code-mode sequestration check (review skill, Code mode 2: `git diff … origin/main...HEAD -- '*/.tracker/**/check.sh' …`).
Evidence (attack spec, case B): the step rewrites `tracker/issues/c0091/check.sh` to `exit 0`, commits, and asks the broker to push. The answer is ok. `git show main:tracker/issues/c0091/check.sh` on origin prints `exit 0`, and the outcome is `ok`, with no tripwire. A z-run agent can do this to its own raft's `check.sh` or specs, then merge `main` into its branch. The code reviewer's three-dot sequestration diff then lists nothing, because the change came in through `main`, not the branch.
Critique: the tempting fix is to refuse every path named `check.sh`. But `./zn status` and `ready` move item folders, which renames them legitimately.
Consequences: the broker needs to know which tracker writes a step's own `./zn` commands make: front matter, `spend.md` rows, new capture folders, review and harvest files, folder moves. Any legitimate write to a sequestered file from inside a step would then have to go through a PR or the dispatcher's own script steps (`z-ready` already runs outside any step).
Recommendation:
- **Refusals.** The shared check (F1) refuses, for broker requests, any content change (not an R100 rename) to an existing `check.sh` or `acceptance/**`.
- **Tripwire.** G18's tripwire applies the same rule to commits it didn't make, so a stolen user credential gets no more than the broker allows.
- **Spec case.** A broker request that edits an existing `check.sh` is refused, and a folder move (R100) passes.
- **Escalate if needed.** If some skill step really must edit a sequestered file from inside a step, escalate to the user: (a) that step's sequestered edits go by PR, or (b) a decision line accepting unreviewed edits of acceptance files.

### F3 [high] The broker force-pushes with the user's credential. A step asked it to move `main` back to an older commit, and a human's code commit disappeared from origin; the tripwire noticed only afterwards.
Where: `brokerPush`: `git push --force-with-lease=refs/heads/main:{lease} origin {sha}:refs/heads/main`, with `lease = base or main`, where `base` comes from the request file; §8's ruleset (`non_fast_forward`, but the admin role bypasses it `always`).
Evidence (attack spec, case D): another terminal pushes `src/feature.lua` to `main`. The step then requests `sha = FETCH_HEAD~1`, `base = FETCH_HEAD`. The merge base is the sha itself, so the diff is empty and the check passes. The force push succeeds, and origin's `main` no longer has `src/feature.lua`. The tripwire then fires ("origin's main was rewritten during the step"), but the rewrite is already on GitHub. With the user's bypass the server never refuses a non-fast-forward from the broker. A rewind to any commit at or after the step's `before` doesn't trip the wire at all: it drops whatever others pushed during the step.
Critique: the tempting fix is to ignore the request's `base`. The lease alone still allows a non-fast-forward.
Consequences: a fast-forward-only broker refuses a request built on a stale `main`. `publish.commit` already rebases and retries on a lease failure, so it must treat the broker's "not a fast-forward" answer the same way.
Recommendation:
- **Fast-forward only.** The broker pushes only when `merge-base --is-ancestor <fresh main> <sha>` holds, and without `--force`/`--force-with-lease` (a plain push, which a moved `main` refuses).
- **Spec cases:** a request for an ancestor of `main` is refused and `main` is unchanged (mutant: force kept); a stale-base request is refused and retried by publish.

### F4 [high] The tripwire watches only the step's own window: a detached process pushes code to `main` after it has run, and commits between steps or after the chain are never checked. That breaks the decision's "a tripwire the agent can't bypass".
Where: §5 "The tripwire" ("after the step's group is gone"); `modelStep` (`snapshot` before, `tripwire` right after `runner.run`); §4 ("A process that left the group (setsid) is not waited for"); the Problem's decision line ("A post-step tripwire the agent can't bypass checks that origin's main moved only as authorised").
Evidence (attack spec, case E): the step runs `perl -e 'setpgrp(0,0); exec @ARGV' sh -c "sleep 4; …; $ZN_REAL_GIT push -q origin HEAD:main"` with its output redirected, and exits. The dispatcher exits 0 with outcome `ok`, and the tripwire is quiet. Seconds later origin's `main` has `late.lua` (`late-push=0`). The next step's `before` is taken after that, so nothing ever compares across the gap. In the fixture the push needs no credential. In real use it is the user's credential, which §5 says plainly a same-user process can read, and the user's admin bypass lets it through. The bot's own token is enough to merge a PR the same way, after the step (F9).
Critique: the tempting fix is to also check at chain end. A process that sleeps longer still escapes, and the setsid gap is the documented "can't be enforced by the OS" case. The decision line claims more than the mechanism gives.
Consequences: closing the gap fully needs an OS boundary (a separate macOS user for steps, whose processes can't read the user's keychain or `~/.config/gh`), which changes how worktrees, `.cache` and the jail are shared. A watermark detects late; it never prevents.
Recommendation: escalate to the user, because the decision's wording doesn't hold:
- (a) **Keep the same-user model, detect late.** Persist a watermark (`.cache/dispatch/main-seen`). The tripwire compares from the watermark, not from the step's `before`. Every dispatcher start and the end of every chain check `main` since the watermark, so a late push stops the next run with exit 5. Record a decision line that a detached process can still act after a step, and is caught only at the next dispatch. Cost: small.
- (b) **Run steps as a separate macOS user** with no access to the user's credentials. This is the only real boundary. Cost: setup by the user, and a redesign of the shared worktree, `.cache` and gate-jail paths.
- (c) **Remove the user's always-on bypass.** The broker's pushes then come from a GitHub App whose key lives where only the dispatcher can read it, which again needs (b) to be real.

Whichever the user picks:
- **Spec case.** A detached late push is caught, by the next run (a) or by the boundary (b).
- **Row.** "the tripwire spans every interval since the last check" (mutant: `before` per step).
Lesson: ticket-prep/required-steps-on-every-path

### F5 [high] The dispatcher's settings come from the main checkout's working tree, and the tripwire ignores untracked files there. A step dropped an untracked `.models.toml` into the main checkout, and the dispatcher then merged its prep PR against the project's `auto_merge = []`.
Where: `dispatcher.settings` (`models.walk(".", item.dir)` from the main checkout's cwd); `dispatcher.resolve` (the same walk, so caps, `max_calls`, `order` and models too); `dispatcher.tripwire` (`git status --porcelain --untracked-files=no`, and `after.status ~= before.status`).
Evidence (attack spec, case F): a GitHub-looking origin rewritten to the fixture, a fake gh, a green open PR #7 for each item, and `tracker/.models.toml` = `[dispatch] auto_merge = []`.
- Control (c0107, the step only claims): exit 4, and no `gh pr merge`.
- Attack (c0106): the step claims, then writes `$main/tracker/issues/c0106/.models.toml` with `auto_merge = ["prep"]` (the main checkout found through `$ZN_DISPATCH_HOME`). The fake gh logs `realgh pr merge 7 --squash`, with no tripwire.
- **The same channel** raises the step's own `max_tokens`/`max_calls` and `stall_seconds` for later steps, or changes their models.
- **The status check misses edits too.** It compares status strings, so further edits to a file that was already dirty before the step go unseen.

Critique: the tempting fix is `--untracked-files=all` in the tripwire. That is detection after the merge decision, in the same process that reads the file, and ignored files would still be unseen.
Consequences: reading settings from `refs/zn-dispatch/main` means an issue's `.models.toml` takes effect only once it is on `main`. The prep PR that adds one doesn't change its own run. That is the safe direction, and the design must say it.
Recommendation:
- **Read from origin.** `models.walk` reads layers from a fresh-fetched origin ref (`git show refs/zn-dispatch/main:<dir>/.models.toml`), never the working tree. This is lesson architecture/guards-trust-only-origin, which §5's own broker already follows.
- **Tighten the tripwire.** It compares untracked files and content hashes (`git status --porcelain --untracked-files=all` plus `git diff --stat HEAD`), not status strings.
- **Spec cases:** an untracked closer file in the main checkout changes nothing (mutant: working-tree walk); an extra edit to an already-dirty file trips the wire.
Lesson: architecture/guards-trust-only-origin

### F6 [high] The prep and raft gates merge whatever the PR holds: `Facts.pr` carries no file list and no head sha, and `merge` doesn't pin the commit it checked
Where: §6.9; `dispatch.gate` (`table.find(f.autoMerge, name) and not pr.draft and pr.green and pr.mergeable`); `dispatcher.facts` (`prView` = `number,state,isDraft,mergeable,statusCheckRollup`); `dispatcher.merge` (`gh pr merge <pr> --squash`); §8 1 (the agent's credential has *Contents: write*, so it pushes any branch, its own `prep-<slug>` included); G4.
Evidence:
- `dispatch.next` with an issue that is preparing and claimed by this run, plus a green, mergeable, non-draft PR #9 and `autoMerge = {"prep","raft"}`, returns `merge prep 9` (run in the clone). No fact about the PR's contents exists to stop it.
- Case F shows the dispatcher's own `gh pr merge 7 --squash` running with the user's credential.
- So a z-design step can commit code to its prep branch, and once CI is green the dispatcher merges it into `main` with no human look.
- G4's premise is that a prep PR is documents, not code.
- Between `facts` and `merge` the head can also move (a detached process, F4), and `gh pr merge` merges whatever the head is then.

Critique: the tempting fix is to make the prep gate a human's too. That changes G4 and the user's chain; it is not the reviewer's to decide.
Consequences: an allow-list for each gate has to name what a prep PR legitimately carries besides tracker state: lesson files under the skills' `lessons/` folders, and `harvest.md`. The list must move with those skills (zz-rules' exhaustive lists).
Recommendation:
- **Facts.** `Facts.pr` gains `head` (the sha) and `files` (`gh pr view --json headRefOid,files`, or the shared check of F1 over a fetch of the head).
- **The rule.** `prep` passes only when every file is tracker state or a skill lesson, and `raft` only when every file is tracker state. Anything else is stop 4, "the prep PR carries code".
- **Merge.** `merge` runs `gh pr merge <pr> --squash --match-head-commit <head>`.
- **Rows and cases:** a prep PR with `src/x.lua` waits at the gate (mutant: no file check); a head that moved after the check doesn't merge (mutant: no `--match-head-commit`).
- **Escalate if needed.** If the user wants prep PRs to carry other files, escalate the list.

### F7 [high] Every top-level dispatcher serves one shared broker folder. Two dispatchers at once crash one of them mid-step, and a request can be answered and recorded by the wrong one.
Where: `modelStep` (`ZN_PUBLISH_BROKER = process.env.ZN_PUBLISH_BROKER or "{home}/broker"`, the same `.cache/dispatch/broker` for every item); `broker.serve` (`fs.removeFile(stem .. ".req")` outside any `pcall`); `runner.run` (`r.onTick()` is not protected).
Evidence: two `broker.serve` loops (A and B) ran on one folder while a client made 8 requests. A died with an error at broker.luau line 54 (removing a `.req` that B had already taken). B answered all 8. In the dispatcher that error escapes `onTick` and `runner.run`, so the dispatcher dies mid-step. Its lifeline kills the step, and the item is `lost`.
- **The wrong dispatcher serves.** A request from A's agent pushed by B lands in B's `st.pushed`. B's tripwire then exempts it, so the wrong dispatcher's exemption covers the commit (and see F1).
- **Two answers.** When both read the same request, the server whose read failed can write a "does not parse" answer before the one that pushed. The client then reports a failed publish that in fact landed.

One dispatcher per item is the design's own rule (the run lock), so dispatching two items at once is the normal case, and c0118's board makes it routine.
Recommendation:
- **A broker per run.** Each top-level run has its own broker folder (`<id>/broker/`), named in the step's environment. A nested step inherits its author's.
- **Claim by rename.** A server claims a request atomically (`fs.move` of `.req` to `.taken`, which fails for the loser) and never raises in `onTick`.
- **Spec case:** two dispatchers on two items, both stepping with claims. Both finish `ok`, each records only its own pushes, and neither crashes.

### F8 [high] The cursor runtimes' `max_calls` fails open: a stream whose lines carry no `model_call_id` counts 0 calls and 0 tokens, so neither cap ever stops the step. That breaks the decision's "fail closed, never unlimited".
Where: `adapters` agent feed (`if type(j.model_call_id) == "string" … acc.calls += 1`); `runner.run` (`acc.calls > maxCalls`, `acc.live > cap` with `live` always 0); E3 ("A call that streams no `model_call_id` … is not counted"); G16; E9 (`cursor-app`'s stream is unproven, "as cursor-cli").
Evidence (the adapters, run in the clone): 500 turns of `thinking`, `assistant` text and a `tool_call` started/completed pair with no `model_call_id` give `calls 0 live 0`, for both `cursor-cli` and `cursor-app`. The runner's two cap checks can then never fire, and a busy session never stalls. The step runs until the CLI stops by itself. Three ways to get there:
- a Cursor release that renames the field;
- `agent worker`'s stream not carrying it (unproven);
- a model that answers without tools.

The adapters spec pins the recorded lines, so none of these turns a spec red. Maintainability's "a CLI that changes its format fails that spec, not the user's night" is wrong here: the spec never sees the live CLI.
Critique: the tempting fix is to count `thinking` blocks as well. That still trusts one more field name.
Consequences: a fallback count can stop a session early. That is safe for spend, and the decision line accepts that N calls is not N tokens.
Recommendation:
- **Fallback count.** Count a model call at each `model_call_id` and, when none is present, at each assistant turn boundary: the first `thinking` or `assistant` line after a `tool_call` `completed` or a `user` line.
- **Fail closed.** A callCapped stream that has shown K tool calls or assistant turns with no `model_call_id` ends the step `failed` ("the agent stream carries no model_call_id: max_calls can't be enforced"). Name K, and make it a row.
- **Ceiling.** Give the callCapped runtimes a wall-time ceiling from `.models.toml`.
- **Cases:** the no-id stream above is stopped (mutant: id-only counting); E9 must show `agent worker`'s lines before `cursor-app` is pinned.
Lesson: architecture/guard-no-is-explicit

### F9 [medium] §8's ruleset doesn't stop the bot from merging its own green PR, and E10 expects the opposite (not reproduced: it needs GitHub)
Where: §8 3 (rules `deletion`, `non_fast_forward`, `pull_request` with `required_approving_review_count: 0`, `required_status_checks`; no `update` restriction); §8 1 (the bot gets *Contents* and *Pull requests* write); §8 4 and E10 ("`gh pr merge <a green PR>` is refused" with the agent's token); the Problem's decision ("can't … merge").
Evidence (reasoned from GitHub's rule semantics, not run): a collaborator with Write may merge a PR once the ruleset's conditions hold. Here those are a PR, the green `gate` check and zero approvals. So the bot's token merges any green PR through the REST API (`curl -X PUT …/pulls/<n>/merge` with `$GH_TOKEN`), which never touches the gh wrapper. During a step the tripwire sees the merge commit afterwards. After a step nothing does (F4).
Recommendation:
- **Restrict updates.** Add `{ "type": "update" }` to the ruleset, so only bypass actors (the admin role: the dispatcher's and the user's merges) can update `main`. Alternatively require one approval from the user, if the user prefers that (escalate the choice).
- **E10.** E10 asserts the bot's direct API merge is refused, not only `gh pr merge` through the wrapper.
- **Check the decision.** Confirm that `update` still lets the admin's tracker pushes through.

### F10 [medium] A `stop` sent between the state going `running` and the runner's start is dropped: the step runs on, and the state flips from `lost` back to `running`
Where: `modelStep` (`save(st)` with `outcome = "running"`, then `snapshot(ctx)`, a fetch, then `runner.run`); `runner.run` (removes `stop` and `pid` at start); `stopAt` (with `st.run` nil and `running`, it writes the marker and saves `lost`).
Evidence (reasoned from the code): `stop` in that window writes the marker and saves `lost`. The runner then deletes the marker as stale and starts the CLI, and `onStart` saves the in-memory state (`running`) over `lost`. The window is a network fetch long, and c0118's stop button can land in it. No case covers it.
Recommendation:
- **Marker.** The runner clears a stale stop marker before `save(st)` marks the run `running`, never after, and checks the marker once more just before it starts the supervisor.
- **No lost while running.** `stopAt` doesn't mark a `running` state `lost` while the item's run lock is held.
- **Case:** a stop written right after the state goes `running` ends the step `stopped`.

### F11 [medium] A nested step picks its folder number by "the first `n` not yet a directory", but makes the directory seconds later, so two parallel stream reviews share `zz-review-stream-1`: review 001 F5's shared state, back
Where: `oneStep` (`while fs.isDir(...-n) do n += 1 end; nested = …`, with the folder made later, in `modelStep`/`save`); §9 (z-run Phase 2B: stream reviews under the dispatcher, in parallel on a CLI with subagents).
Evidence (reasoned): two `./zn dispatch zz-review <issue> --mode stream` started together from one author both see `-1` free. The name doesn't carry the issue id. They then share a `pid`, `stop`, `run.lock` (the second supervisor dies "the run is held") and `state.json`.
Recommendation: claim the folder atomically (`mkdir` without `-p`, retried at `n+1`), and put the item id in the name (`zz-review-stream-<id>-<n>`). Case: two nested reviews started at once get two folders and both finish.

### F12 [low] The document contradicts itself on two numbers
Where: §5 ("wait for the answer (`<uuid>.res`, up to 600 s)"), against G19 and `broker.WAIT_SECONDS = 120`; G14 (`size: 4300`), against the front matter's `size: 3700` and Size.
Recommendation: pick one value for each and say it once. A publish that waits on a broker while the top dispatcher is fetching for the tripwire needs the longer wait.

Candidate lessons (for the lead):
- One definition of "tracker state", shared by every guard that judges it. Read it from `diff-tree --raw --no-renames`, both sides and modes, never `--name-only`. Check: does every guard that lets "tracker-only" changes through use the same function, and does it see a rename's source, a mode change, and a prefix that is a sibling rather than a folder?
- A tripwire covers every interval, not only the step it wraps. Check: what happens between two checks (after a step, between steps, after the chain), and can a process outlive the window it is checked in?
- A merge gate checks what it merges and pins the commit it checked. Check: which facts about the PR's contents does the gate read, and can the head change between the check and the merge?

Verdict: changes
