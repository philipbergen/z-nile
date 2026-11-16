# Review 003: c0117 (design mode)
Inputs: `prep-c0117` at 956a898 (`z-nile/.tracker/issues/c0117/{c0117.md,check.sh,harvest.md,acceptance/*}`, `design-review-002.md`, `design-refute-002.md`); prototype `.worktree/proto-c0117` at 6af3daf on b57df84, read only; `./zn capture c0117` (fb7fd80, no marker); `./zn lessons --when design --full`; the three new lessons `architecture/{one-definition-of-tracker-state,tripwire-covers-every-interval,merge-gate-checks-what-it-merges}`. The attacks ran in a scratch clone of the prototype under the session scratchpad, with origin pointed at a path that doesn't exist. They ran through `lune run tests/run` (the jail), in `.cache/c0117-attack3*` fixtures, with the same extra fake mode round 2 used (`script`: the fake CLI runs `$FAKE_DIR/script.sh` inside a dispatched step). Three specs: `attack` (6 cases), `pure` (3), `extra` (3), plus round 2's attack spec ported to the new broker protocol. A few git probes ran in scratch repositories. No real CLI, no network, no real origin. `./zn check c0117` in the clone: 11/11 criteria pass.
Dropped from review-002: F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12. Each fix holds against round 2's own attack (below). Several of the new mechanisms have holes of their own:
- round 2's F1 and F2 (the one tracker-state function): F1, F8 and F10 here;
- F4 (the watermark): F2, F3 and F6;
- F5 (settings from `main`): F4;
- F6 (the merge gate's file check): F5;
- F8 (the fallback count): F7.

Scope (item 11): the capture is confirmed. The new `Decided with the user (2026-10-21)` block ("Persisted watermark") is dated, and the Problem is otherwise unchanged. Two captured outcomes rest on mechanisms that fail open. "Stops at the cap" fails open for the cursor runtimes (F7). The decision's watermark "in a file outside any agent's reach" isn't outside the step's reach (F2).

Guesses:
- **G20** is not reasonable as written. Its stated cost ("a PR merged by anyone with write access passes, which the ruleset already limits to the user's and the dispatcher's merges") is wrong twice. `prMerged` accepts a PR merged into any branch, and the ruleset covers only `main`. And the watermark exists to catch the user's credential used from a step, but that credential can always produce "a merged PR's merge commit" (F6). The first-run trust half is also a hole now, because a step can delete the file (F2).
- **G21** (the `update` rule rather than one required approval) is reasonable. It keeps the dispatcher's gates unattended, and it is the only way §8's design works without the user approving every prep. It closes round 2's F9 for `main` only, so the base-branch check that F6 asks for is needed with it. E10 still has to show that the admin's tracker pushes get through `update`.

### F1 [high] A "pure move" pairs any deletion with any addition of the same blob and name, and lets every new sequestered file through. A step replaced an item's `check.sh` on `main` and took its acceptance spec away through the broker. On macOS, adding a file that differs only in case overwrites `check.sh` in every checkout that pulls.
Where: `trackerstate.judge` (`added[newBlob..":"..newMode]`, `basename(a.path) == basename(e.path)`, `e.status ~= "A"`); §5 "Tracker state" ("a new item's stub is an addition and passes"); Rules and mutants row M94; round 2's F2 (the same rule, now through a new mechanism).
Evidence:
- **Attack spec, case S: a decoy move, through the broker.** On `main`, `tracker/issues/c0091/` holds `check.sh` (a real check) and `acceptance/hard.spec.luau`. The step runs one commit with four changes and asks the broker to push it:
  - `git mv c0091/c0091.md done/c0091/c0091.md`;
  - `git mv c0091/check.sh c0099/check.sh` (the decoy: the same blob, the same name);
  - `git mv c0091/acceptance/hard.spec.luau c0099/acceptance/hard.spec.luau`;
  - write a new `done/c0091/check.sh` containing `exit 0`.

  The broker answers `{"ok":true,"message":"pushed"}`. `git show main:tracker/issues/done/c0091/check.sh` on origin prints `exit 0`. c0091 has no acceptance spec left. The step's outcome is `ok`, and the watermark vetted the commit after the step, because both use the same function. The deletion pairs with the decoy, and the weak `check.sh` is an "addition".
- **Case-folding (scratch repository, macOS, `core.ignorecase=true`).** A commit adds `tracker/issues/c0091/CHECK.SH` containing `exit 0` next to the existing `check.sh`. `diff-tree --raw --no-renames` prints one line, `A tracker/issues/c0091/CHECK.SH`, which `judge` passes as a new stub. A `git pull` in another clone then leaves `check.sh` containing `exit 0`, and `git status` shows ` M tracker/issues/c0091/check.sh`. Git says "addition", but on macOS the working tree says "the check changed". `./zn check c0091` in a worktree that pulled then runs `exit 0`.
- **The rule is also wrong the other way (reasoned).** `moveOnOrigin` (`ready`, `stop`, `done`) sends every moved `check.sh` through `paths.rewrite` (c0067), so a `check.sh` that names its own item's path changes blob on a legitimate move. That is no longer a pure move:
  - `./zn done` inside z-run, through the broker, is refused;
  - a `ready` from the `z-ready` script step trips the watermark at the next step.

  Today's backlog has no such `check.sh`. `done/c0067`, `c0069` and `c0071` did, and nothing stops the next one.

Critique: this is the second round that finds a hole in the sequestered rule, so the mechanism is what's wrong. "Same blob, same basename, anywhere in the commit" isn't what a move is. A move is one item's folder going from one lifecycle folder to another. The tempting fix is to also require the same item id in both paths. Case S still works with that fix if the decoy is a second folder of the same id, and it still misses case-folding and the rewrite.
Consequences: judging per item needs the item id from each path (`<root>/issues/[<lifecycle>/]<id>/…`, `<root>/rafts/…`). Allowing the rewrite needs the expected content (`paths.rewrite` of the old blob for that move). Case-folding needs the resulting tree, not only the diff.
Recommendation: question the mechanism. Judge sequestered files per item, not per blob.
- **The rule.** For each item id the change touches, map every sequestered file to its path relative to the item folder. The map before and the map after must hold the same set of relative paths. Each must hold the old content, or `paths.rewrite(old, the move's dirs)` when the item's folder moved. Only an id that doesn't exist on the base may add sequestered files (a new item's stub).
- **Case and normalisation.** Refuse any path in the resulting tree whose case-folded, NFC form equals another path's (`git ls-tree -r` of the result, or the base's paths plus the added ones). Refuse a sequestered name that isn't exactly `check.sh` or under `acceptance/` in lowercase.
- **Rows and cases:**
  - the decoy swap of case S is refused (mutant: blob pairing);
  - a spec moved to another item is refused;
  - an added `CHECK.SH` next to `check.sh` is refused (mutant: no fold);
  - a `ready` whose `check.sh` names its own path passes through the broker and the watermark (mutant: blob equality only).
Lesson: architecture/one-definition-of-tracker-state, testing/seed-every-enumerated-case

### F2 [high] The watermark is a file the step can write, and a missing watermark is trusted. A step pushed code past the wrapper and deleted the watermark (or set it to the new `main`), and the tripwire after that same step stayed quiet.
Where: `dispatcher.watermarkPath` (`ZN_WATERMARK_DIR`, else `XDG_STATE_HOME`, else `HOME`, which the step's environment inherits from `process.env`); `vetMain` (`if not mark then writeWatermark(ctx, fresh); return nil`, and `if mark == fresh then return nil`); `tripwire` (vets from the file, not from the step's `before`); the Problem's decision line "in a file outside any agent's reach"; §5 "an agent … can still write the watermark file or run `vet` itself: both are the user's, by rule".
Evidence (attack spec):
- **W1.** The step prints `wmdir=<fixture>/watermark` (the variable is in its environment). It commits `w1.lua`, runs `$ZN_REAL_GIT push origin HEAD:main` (`realpush=0`), then runs `find "$ZN_WATERMARK_DIR" -name main-seen -delete`. The dispatcher exits 0, the outcome is `ok`, there is no TRIPWIRE, origin's `main` has `w1.lua`, and the next run exits 0. After the step, `vetMain` finds no file and takes `main` as it is.
- **W2.** The same push, then the step writes `git rev-parse HEAD` into `main-seen`. Outcome `ok`, quiet: `mark == fresh`.

This is worse than round 2. There, a push inside the step's window was caught by the step's own `before`. Now the window check reads the same file the step can delete. One `rm` defeats the in-step tripwire, not only a late one. The decision's "outside any agent's reach" doesn't hold: the agent runs as the same user with `--sandbox disabled`, and the path is in its environment.
Critique: the tempting fix is to hide the path (strip `ZN_WATERMARK_DIR` from the step's environment). `~/.local/state/zn-dispatch` is the documented default, and the key is the git common directory, which every worktree shares.
Consequences: a watermark the same OS user can't write needs an OS boundary, or state the step can't reach (the server). Without one, the dispatcher can still close the in-run hole and fail closed on a missing file. Between runs a rewrite stays possible, and the decision line must say so.
Recommendation: escalate to the user, since the decision's words don't hold. Options:
- (a) **Close what can be closed, and amend the decision.**
  - The dispatcher vets from the watermark it holds in memory for the whole run, never from a file it reads back.
  - A file that differs from what this dispatcher last wrote, or is missing once one has been written, is a tripwire, not trust on first use.
  - The first watermark is written only by `./zn dispatch vet`, so no run trusts on its own.
  - The decision line says a process left behind can still rewrite the file between runs.
  - Cost: small.
- (b) **A separate macOS user** owns the watermark folder and runs the dispatcher's vetting. This is the only real boundary, at the setup and redesign cost round 2's F4 (b) named.
- (c) **A server-side watermark**: a ref (`refs/zn/main-seen`) that only bypass actors may update. It still falls to a stolen user credential, so it needs (b) to be real.

Whichever the user picks, add rows and cases: a step that deletes or rewrites the watermark trips the wire after that step (mutants: re-reading the file, TOFU on a missing file).
Lesson: architecture/tripwire-covers-every-interval, architecture/guards-trust-only-origin

### F3 [high] Origin's URL comes from the repository configuration the step shares, so a step can blind the watermark: it pushes code, points `remote.origin.url` at a frozen copy and `pushurl` at the real origin, and every later vet reads the copy
Where: `freshMain` and `broker.push` (`git fetch origin …` in `ctx.mainRoot()`); every worktree shares `.git/config` with the main checkout; `tripwire` compares the main checkout's status, diff and HEAD, never its configuration.
Evidence (extra spec, case R): the step does four things.
- It bare-clones origin to `.cache/…/frozen.git`.
- It commits `r.lua` and pushes it with `$ZN_REAL_GIT push origin HEAD:main` (`realpush=0`).
- It runs `git config remote.origin.url <frozen.git>`.
- It runs `git config remote.origin.pushurl <the real origin>`.

The dispatcher exits 0 with no TRIPWIRE, and origin's `main` has `r.lua`. After the step, `vetMain` fetched the frozen copy, whose `main` equals the watermark, and passed. The main-checkout check looks at status, diff and HEAD, and none of them moved. The blinding lasts as long as the copy does (reasoned). In my fixture the copy was gone by the next run, which then tripped on "origin's main could not be fetched", so a copy kept somewhere stable is the attacker's one extra step.
Critique: round 1's F1 and F2 moved the wrapper onto the URL the dry run actually reports. The dispatcher's own fetches still trust `origin` as the shared configuration resolves it (`url`, `pushurl`, `insteadOf`, `pushInsteadOf`), and every step can write that configuration.
Consequences: the dispatcher needs origin's URL from somewhere the step can't write. The value it reads at its own start is the natural choice, since the dispatcher starts before any step and the run lock keeps one dispatcher per item. Nested dispatchers inherit it. The specs' fixtures already use `insteadOf`, so the rule must be a URL fixed once per run, not "no `insteadOf`".
Recommendation:
- **One URL per run.** At the start of each top-level run, read origin's fetch URL and push URL (`git ls-remote --get-url origin`, `git remote get-url --push origin`). Every fetch and push the run makes (the broker, `vetMain`, the gates' fetch from F4) names those URLs, never `origin`.
- **Configuration in the tripwire.** The tripwire also compares `git config --list --show-origin` of the repository before and after each step, and a change trips it.
- **Persist across runs.** Keep the URL beside the watermark too, so a change between runs trips the next one (its write is as weak as F2's, said in the same decision line).
- **Cases:** case R trips (mutant: `origin` by name); a step that only adds a `pushurl` trips.
Lesson: architecture/guards-trust-only-origin, testing/derive-after-stripping-overrides

### F4 [high] A step raises its own limits and turns on its own merge gate through tracker state: an item's `.models.toml` lies under a tracker root, so the broker pushes it, and the next run merged the prep PR against the project's `auto_merge = []`
Where: `trackerstate.judge` (anything under `<root>/` is tracker state); §1 ("optionally closer to the work: … an issue's folder"); `models.walkAt` (settings from `main`); `dispatch.prFiles` (a prep PR may carry anything in its issue's folder); round 2's F5 (the same channel through the working tree).
Evidence (attack spec, case MT): the project's `tracker/.models.toml` says `auto_merge = []`, and PR #7 is green with `files` inside `tracker/issues/c0106/`.
- **First run.** The step claims the issue (`./zn status preparing`), writes `tracker/issues/c0106/.models.toml` with `auto_merge = ["prep"]` and `stall_seconds = 99999`, commits, and asks the broker. It is `pushed`, and that run stops at the gate ("waits for a merge").
- **Second run.** The log has `realgh pr merge 7 --squash --match-head-commit feedface`.
- **The same channel** sets `max_tokens`, `max_calls` (the user's cap), `tool_seconds`, `order` and `runtime` for every later step on the item. The project root's own `.models.toml` sets them for every item of the project. A prep PR that adds the same file passes `prFiles` and is auto-merged, so §1's "takes effect only after that PR merges (the safe direction)" isn't safe: the dispatcher does the merging.

Critique: round 2's fix read the settings from `main`, which is right, but `main` takes tracker state without review. A setting that grants authority (a gate, a cap) is configuration, not tracker state.
Consequences: `.models.toml` files then change only by a reviewed PR that a human merges. A skill step that wants an issue-level spec must ask (questions.md).
Recommendation:
- **Not tracker state.** The one function refuses `.models.toml` anywhere, alongside `.gitattributes`.
- **The gates.** `prFiles` and the F5 gate check refuse a PR that carries one, which leaves it to a human.
- **Cases:** case MT's broker push is refused (mutant: `.models.toml` allowed); a prep PR carrying an item's `.models.toml` waits at the gate.
- **Escalate if needed.** If the user wants agents to tune their own items' specs, escalate: the keys that grant authority (`auto_merge`, the caps, `stall_seconds`, `tool_seconds`) may then be lowered but never raised by a closer file.
Lesson: architecture/guards-trust-only-origin

### F5 [high] The merge gates judge a PR from gh's `files` list, which hides a rename's source, stops at 100 files, and (for a rafting PR) admits every item's `check.sh` and acceptance specs. That is a fifth definition of tracker state.
Where: `dispatcher.parsePr` (`files[].path`); `dispatch.prFiles` (prep: `folder .. "/"` or `isLesson`; raft: `root .. "/"`); `main.luau` `prView` (`gh pr view --json …,files`); the merged commit then passes the watermark as a PR merge (G20).
Evidence:
- **gh's own query.** `strings` of the installed gh 2.102.1 shows `files(first: 100) { nodes { additions, deletions, path, changeType } }`. That is the new path only, with no previous path, and at most 100 files.
- **P1 (pure spec).** A prep PR that `git mv`s `src/guard.lua` into `tracker/issues/c0091/` reaches the gate as `{ "tracker/issues/c0091/guard.lua" }`. `prFiles("prep", …)` returns nil, so the dispatcher merges it, `src/guard.lua` is gone from `main`, and the watermark vets the squash commit as a PR merge. This is round 2's F1 at the gate.
- **P2.** A rafting PR carrying `tracker/issues/c0091/check.sh`, `…/acceptance/hard.spec.luau` and `…/.models.toml` (another item's) passes: round 2's F2 at the gate.
- **101 files (reasoned).** A PR with 100 tracker paths that sort first and `zzz.lua` lists only the 100.

Critique: the lesson the author wrote this round says every guard calls one function, and this guard doesn't. Patching `prFiles` with `changeType` and a page loop is the parser problem again.
Consequences: the gate needs the PR's commits locally. A pinned fetch of the head is one more fetch per gate.
Recommendation: question the mechanism.
- **Use the one function.** The gate fetches `refs/pull/<n>/head` (from F3's URL) into a private ref, and refuses unless it equals `headRefOid`. It judges `merge-base(fresh main, head)..head` with `trackerstate.check`, plus the gate's narrower allow-list:
  - prep: the issue's own folder (its own sequestered files editable) and lessons;
  - raft: the project root, sequestered for every item that isn't the rafting PR's own, with no `.models.toml` (F4).
- **Merge.** It merges with `--match-head-commit` (kept).
- **Cases:** P1 and P2 wait at the gate (mutants: gh's file list, no sequestered rule for the rafting gate); a PR whose fetched head differs from `headRefOid` waits.
Lesson: architecture/one-definition-of-tracker-state, architecture/merge-gate-checks-what-it-merges

### F6 [high] G20 vets any merged PR's merge commit, whatever branch it merged into, and any PR merge made with the user's stolen credential. The watermark is then blind to code that arrives as a merge.
Where: `main.luau` `prMerged` (`.[] | select(.merged_at != null and .merge_commit_sha == "<sha>")`, with no `base.ref` check); `vetMain` (`if why and not ctx.prMerged(sha)`); §8 3 (the ruleset targets `~DEFAULT_BRANCH` only); G20.
Evidence:
- **The filter (run).** `jq` with that filter over a GitHub-shaped `commits/<sha>/pulls` answer for PR #12 (`merged_at` set, `merge_commit_sha` = sha, `base.ref = "side"`) prints `12`.
- **The bot's half (GitHub semantics, not run).** The bot (*Contents* and *Pull requests* write) can create `side`, open `evil → side`, and merge it. No ruleset covers `side`.
- **The rest.** Landing that merge commit on `main` takes the user's credential: a detached process using `git credential-osxkeychain`, the case §5 says the watermark is for. `vetMain` then judges the commit as code, asks `prMerged`, gets true, and moves on. The same process can simply merge a PR into `main` with the user's token (`gh api -X PUT …/merge`, admin bypass), and G20 passes that by design.

Critique: the tempting fix is `base.ref == "main"`. That closes the side branch, but not a stolen-credential merge into `main`, which GitHub can't tell apart from the user's own.
Consequences: a dispatcher-merged PR can be recognised (it is in `state.merged`, which the step can write, the same weakness as F2). A human's merge can't be told apart from a stolen-credential merge without a second factor.
Recommendation:
- **Base branch.** `prMerged` also requires `.base.ref == "main"`. Case: a PR merged into another branch is unvetted (mutant: no base check).
- **Escalate the rest to the user**, as G20's decision:
  - (a) accept that a merge made with the user's credential passes, as a decision line that names it;
  - (b) every code merge not in the dispatcher's own merge record stops the chain until `vet`. Human merges then cost one `vet` each, and the record shares F2's weakness;
  - (c) the required-approval alternative of G21, which a stolen credential can also forge.
Lesson: architecture/tripwire-covers-every-interval

### F7 [high] The cursor runtimes' fallback count still fails open: a stream of tool calls with no `model_call_id` and no `thinking` or `assistant` line counts 0 calls and is never `cap-unknown`
Where: `adapters` `agentFeed` (a turn starts only at a `thinking` or `assistant` line; `noIdTurns` counts only turns); `runner.run` (`acc.unknown` or `acc.calls > maxCalls`); G16; round 2's F8.
Evidence (pure spec, P3): 500 pairs of `{"type":"tool_call","subtype":"started","call_id":"x<i>"}` and `…"completed"…` through `cursor-cli`'s feed give `calls 0 unknown nil live 0`. The runner can't stop the step. While a tool is open the stall limit is `tool_seconds`, and between tools the stream never goes quiet. A model that calls tools without text and doesn't stream thinking (agent prints thinking only for some models; E3's probe used `--stream-partial-output`, which the argv in §4 doesn't pass), combined with a release that drops `model_call_id`, runs unbounded. The decision says "never unlimited". Round 2 also recommended a wall-time ceiling for the call-capped runtimes, and the refute doesn't address it.
Recommendation:
- **Count tool calls too.** A `tool_call` `started` with no `model_call_id`, outside a counted turn, starts a turn (a call). `NO_ID_TURNS` counts those turns too.
- **Ceiling.** Add `max_minutes` for the `agent` specs (a required key, like `max_calls`), or say why not and escalate.
- **Case:** P3's stream stops as `cap-unknown` (mutant: turns only at thinking/assistant).
Lesson: architecture/guard-no-is-explicit

### F8 [medium] The `.gitattributes`/`.gitmodules` refusal compares exact case, and judge accepts `..` components. The broker pushed `tracker/.GITATTRIBUTES`, which git on macOS obeys, and one such line stops every tracker commit on a Mac.
Where: `trackerstate.judge` (`name == ".gitattributes" or name == ".gitmodules"`; `under` by prefix, with no component check).
Evidence:
- **Attack spec, case GA.** The broker pushed `tracker/.GITATTRIBUTES` (`* -text`), and the outcome is `ok`.
- **What macOS git does with it (scratch repository).** With `tracker/.GITATTRIBUTES` = `*.md working-tree-encoding=UTF-16`, `git check-attr` reports the attribute, and `git add tracker/a.md` fails with `fatal: BOM is required … if encoded as UTF-16` (exit 128). Every `./zn` publish of a tracker document on the user's Mac then fails until a human removes the file.
- **`..` components.** A tree made with `git mktree` holding `tracker/../x` prints `A tracker/../x` from `diff-tree`, and `judge` passes it. `git fsck` only warns `hasDotdot`, and checkout refuses the path. That is low on its own, but it is the same component blindness.

Recommendation:
- **Fold case.** Compare the case-folded basename against `.gitattributes`, `.gitmodules` and `.models.toml` (F4).
- **Refuse bad components.** Refuse any path component that is empty, `.`, `..` or `.git` (case-folded). This joins F1's tree-level fold check.
- **Cases:** `.GITATTRIBUTES` and `tracker/../x` refused (mutant: exact-case compare).

### F9 [medium] `vet` ignores `--dry-run`, which its own usage offers: `./zn dispatch vet --dry-run` moves the watermark over an unvetted code commit
Where: `dispatcher.main` (`first == "vet"`: `vetMain`, then `writeWatermark(ctx, fresh)` unconditionally); the usage `… | vet [--dry-run]`; §5 ("A dry run starts nothing, takes no lock and writes nothing").
Evidence (extra spec, case V): a code commit is pushed straight to origin's `main`. `./zn dispatch vet --dry-run` prints "main has <sha>, which the dispatcher did not vet: src/x.lua is not tracker state", then "main vetted at <sha>". The next `./zn dispatch z-design c0101` exits 0, where it should stop with 5.
Recommendation:
- **Dry run.** `vet --dry-run` prints the unvetted commits and writes nothing.
- **Plain `vet`.** It prints each commit it accepts, so the user sees what they vetted.
- **Case:** after `vet --dry-run` over a code commit, the next run still stops with exit 5 (mutant: the flag ignored).

### F10 [low] The broker judges only the combined change `fresh..sha`, while the watermark judges each first-parent commit, so the broker pushes what the watermark then refuses
Where: `broker.push` (`trackerstate.check(git, fresh, sha, …)`); `vetMain` (each commit against its parent).
Evidence (extra spec, case B): the step commits `c.lua`, then `git rm c.lua`, and asks the broker for the second commit. The broker answers `pushed`, because the combined change is empty. The tripwire after the step then fires ("main has <sha>, which the dispatcher did not vet: c.lua is not tracker state"), and the run exits 5. An honest step that committed and reverted a stray file on its branch stops the chain at exit 5.
Recommendation: the broker judges each commit of `fresh..sha` (first-parent, against its parent) as `vetMain` will, and refuses a request whose history `vetMain` would refuse ("squash it and ask again"). Case: a code-then-revert request is refused and `main` is unchanged.

### F11 [low] The new lesson `merge-gate-checks-what-it-merges` tells the next raft to read the PR's `files`, the source F5 shows is unsound
Where: `z-nile/skills/zz-arch/lessons/merge-gate-checks-what-it-merges.md`, "How to apply" (`headRefOid` and `files` in the PR facts).
Recommendation: point it at the one definition: fetch the head pinned to `headRefOid` and judge it with the shared tracker-state function. Add "a rename's source, and more than 100 files" to its check.

Round 2 rechecked (its attacks against the new prototype): round 2's attack spec, ported to the token protocol, against 6af3daf:
- A (rename out of `src`): refused ("src/guard.lua is not tracker state").
- B (edit `check.sh`): refused ("sequestered").
- C (`z-nile/nextgen/`): refused.
- D (rewind): refused ("not a fast-forward"), and origin's `main` is unchanged.
- E (a detached late push): the next run exits 5.
- F (an untracked `.models.toml`): the tripwire fires.

The run lock and nested-folder fixes (round 2's F7, F10 and F11) are covered by `trackerstate.spec` and `control-cli.spec`, which pass.

Candidate lessons (for the lead):
- A sequestered file is judged per item, not per blob. Check: can a deletion pair with an unrelated addition elsewhere in the commit, can a new file stand in for an existing one (another folder, another case), and does a legitimate move that rewrites content still pass?
- A guard's state must be out of reach of what it guards, or be checked against a copy the guarded process can't touch. Check: can the guarded process delete or rewrite the guard's record (a file, a config, a remote URL), and what does the guard do when the record is missing or changed?
- Configuration that grants authority is never "tracker state". Check: does any allow-listed path hold a setting that raises a limit, turns on a gate or changes which tool runs?

Verdict: changes
