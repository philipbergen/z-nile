# Review 003: R0210 (design mode)
Inputs: prep worktree `0ff1df9` (R0210.md, R0210/check.sh, c0640.md, c0640/check.sh, c0640/acceptance/fence.spec.luau and lock.spec.luau, design-review-001/002, design-refute-001/002); prototype `proto2-c0640` `88c196b` (`git diff 01395fc..HEAD -- tests scripts AGENTS.md .claude`: scripts/lib/fence.sh, scripts/lib/git-hooks/*, scripts/lib/ac.sh, tests/lib/fence.luau, tests/run.luau, tests/tooling/repo-fence.spec.luau, the skill and AGENTS.md texts); `origin/main` `9fa1499`; read-only `git worktree list`, `ls-tree` and `config --get-regexp`. All experiments ran in a fresh repository under the session scratchpad. No state was changed in any repository of this project.
Dropped from design-review-002: F1, F2, F3, F4, F6. Their refutations hold. The c0640 specs now check the fixture before every git call they make (`fixture()`), and each probe checks its own repository. A fixture identity refuses the run. The jail closes, on macOS, the gaps F3 listed, and the docs now describe the ref guard honestly. The fetch exception keeps deletions refused. F5 is repeated as F1 with new evidence. F2's precondition holds, but its message has a new problem (F4).

Summary: on an unsandboxed Mac the jail delivers what it claims. A spec can't write the checkout, the main checkout or the shared `.git`, whatever path it takes. I found no way for a spec to damage the local repository there. What's left is at the edges: the network side (the shared GitHub origin), runs inside another sandbox, one jail rule with no test, a runner message that contradicts the stop rule, and a raft-id collision with main.

### F1 [high] (repeat of review-002 F5) "Specs push to no network remote and have no GitHub credentials" is false for scp-style URLs and for git's own credential helper, and AC2 passes anyway
Where: `scripts/lib/git-hooks/pre-push` (`*://* | *@*:*)`, then `[ -d "$url" ] || exit 0`); c0640 Environment guards steps 4-5; AC2; testing skill "Push guard"
Evidence:
- In scratch, I ran the prototype's `pre-push` with `PICKMAN_FENCE_NO_NETWORK_PUSH=1`:
  - `https://github.com/x/y.git` and `git@github.com:x/y.git` exited 1 (refused);
  - `github.com:x/y.git` and `gh:x/y` (an ssh host alias) exited **0** (allowed).
  - A user-less scp-style URL matches neither network pattern. It then falls through to the local-path branch, which allows anything that isn't an existing directory. With a `Host github.com / User git` stanza in `~/.ssh/config`, which is common, that push reaches GitHub with the user's key (`~/.ssh/id_rsa` exists on this machine).
- Credentials:
  - `git config --show-origin --get-all credential.helper` gives `osxkeychain`, from Xcode's system gitconfig. Specs mode clears only `GH_TOKEN`/`GITHUB_TOKEN` and gh's config dir.
  - Every https git operation in a spec can therefore still authenticate to GitHub. Today `pre-push` is the only thing standing between a spec and a write to the shared origin, and the jail doesn't touch the network.
- The `github` probe and gate case 5 test only `https://github.com/x/y.git`. So AC2 ("push to no network remote") passes on an implementation that misses a URL form, and the prototype is such an implementation.
Critique: Review-002 F5 recommended "refuse every URL that doesn't resolve to a local directory". The refute implemented a list of network patterns instead, and a pattern list has gaps. The tempting fix is to add `*:*` to the pattern list. That would also catch a local path containing a colon, and the next form (`ext::`, an `insteadOf` alias) would come back as next round's finding.
Consequences: inverting the check means that in specs mode a push to a local path that doesn't exist yet is refused, but git would fail that push anyway. A spec that needs a credential helper would break, and none does: the full gate passes with no network.
Recommendation:
- In specs mode, `pre-push` allows a push only when `$2` (after stripping `file://`) is an existing directory whose common git dir is not protected. Everything else is refused, before any URL parsing.
- Specs mode also injects `credential.helper=` (an empty value resets the helper list; command scope is read last), `GIT_TERMINAL_PROMPT=0`, unsets `SSH_AUTH_SOCK`, and sets `GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null'`. Checks mode keeps all of these for `ci-verify.sh`.
- Extend the `github` probe and gate case 5 to require refusal for `github.com:x/y.git`, `ssh://git@example.invalid/x.git` and `ext::sh -c true`, and add a check that `git config --get-all credential.helper` ends with an empty value.
- Add mutants N3 "pattern list instead of local-only" and N4 "helpers kept". Reword "no GitHub credentials" to say exactly which credentials are removed.

### F2 [medium] Inside another sandbox the gate always fails, while the Risks and the docs say the run "relies on the outer one"
Where: R0210 Risks, "Runs inside another sandbox … the gate spec's jail case shows whether the outer sandbox protects the checkout"; `repo-fence.spec.luau:116` (`t.expect(env.PICKMAN_TEST_JAIL).toBe("sandbox-exec")`); fence.spec "the gate spec fails …" comment ("the gate's jail case rightly fails here"); AGENTS.md paragraph; testing skill, Jail bullet and Caught-only-by-review
Evidence:
- Case 4 fails whenever `PICKMAN_TEST_JAIL` isn't `sandbox-exec`, without probing anything. Every top-level run started from a sandboxed shell (on macOS, Claude Code's Bash sandbox is Seatbelt, and this harness offers it) is therefore red on `repo-fence`. `scripts/check.sh --full`, RC0 and AC6 can then never pass. Nothing tells the agent what to do except stop.
- The documents describe a different behaviour: Risks says the case "shows whether the outer sandbox protects the checkout", the testing skill says such a run "relies on the outer one", and the review list says these runs "are not jailed again". AGENTS.md's list of what the runner can't see leaves this case out.
- A typical agent sandbox allows writes to its cwd, which is the checkout. So "relies on the outer one" usually means the checkout isn't protected at all.
Critique: The user asked for the boundary to be clear, and here the code, the risk analysis and three documents disagree. The tempting fix is to delete the Risks sentence. That leaves sandboxed agents with a permanently red gate and no documented way out.
Consequences: whichever behaviour is chosen, the fence spec's `jailCase` exemption and the "a run inside a sandbox" case have to agree with it.
Recommendation: make case 4 behave as the Risks text says.
- Under `outer sandbox …`, run the same two probe writes, and pass only if both are denied.
- That fails honestly under an outer sandbox that allows writes to the checkout. The failure message then says: "run specs outside the agent sandbox (it can't be nested and allows writes to the checkout)".
- Put that sentence, and the outer-sandbox case, in AGENTS.md's "what it can't see" list and in the testing skill.
- Add a mutant row: "outer sandbox accepted without probing".

### F3 [medium] The jail's main-checkout rule has no case and no mutant, and it is the rule that protects every other worktree
Where: c0640 "The jail" profile line `(deny file-write* (subpath "<main checkout>"))`; `fence.luau:259-264`; gate case 4 (probes only `<here>` and `<common git dir>`); Rules and mutants rows J1/J2
Evidence:
- Every gate run in this project happens in a worktree under `<main>/.worktree/`. There, `<here>` and `<common>` don't cover the main checkout's files or the sibling worktrees.
- Only the third deny covers them. Delete it (mutant J4) and case 4 still passes: both probes still fail, and J1/J2 don't touch it.
- The c0640 specs can't catch it either: their inner runs are always "outer sandbox" (nested), so no spec ever runs the profile itself. E14 checked it once, by hand.
- What it protects is concrete. `tracker.sh` computes the main checkout from the common dir (`launch`, `worktree`, `worktree-prune`), so a spec running such a subcommand outside a fixture acts on `<main>` and `.worktree/*`.
Critique: Review item 0: a plausible mutant nobody listed is a finding. The tempting fix is a row marked `reasoned`, but this is the one jail rule that a mistake in path arithmetic (the `gsub("/%.git$")`) would silently break.
Consequences: the probe is meaningful only when `<here>` ≠ `<main>`. A run in the main checkout (which the project forbids editing) must skip it.
Recommendation: case 4 also probes `<main>/.pickman-jail-probe-<pid>` when the common dir's parent isn't `<here>`, and removes the file if the write succeeds. Add row J4 "main checkout not denied", `run`. Optionally, also probe a sibling `.worktree/` entry when one exists.

### F4 [medium] The identity refusal tells the agent to repair the shared config, against the stop rule, and names the wrong scope when the value is global
Where: `fence.luau:285-291` (message: `Repair it (git config --local --unset user.email, then check user.name) before running specs`); c0640 Run guards step 1 ("naming the repair"); execute-raft stop condition ("a refused fixture identity … never repair the shared git configuration yourself"); testing skill "If the tripwire fires"
Evidence:
- The runner's own output is a repair command for the shared `.git/config`. Execute-raft, the testing skill and AGENTS.md all say: stop, report, never repair it yourself. An agent reading the failure in front of it will follow the command, because it's the more specific instruction.
- The check reads the effective `user.email`, which includes global config. When the fixture identity comes from `~/.gitconfig`, `--local --unset` changes nothing, or deletes nothing useful, and the run keeps refusing.
Critique: Review-002 F2 asked for "a message that doesn't invite self-repair". The tempting fix is to delete the command from the message. That hides from the user, who does the repair, the one thing they need: where the value came from.
Consequences: none beyond the message and the docs.
Recommendation:
- The message ends `Stop and report this; do not repair it yourself (testing skill, If the tripwire fires).`
- For the user, it prints `git config --show-origin --get user.email`, so the scope is visible.
- The fence spec's identity case also asserts `has(r.stderr, "do not repair")`.
- Add it to the "If the tripwire fires" text.

### F5 [medium] Raft id R0210 is already taken on main, and the prep base is stale again
Where: R0210 frontmatter and every reference; R0210 "Order & dependencies" ("Prep is rebased onto `01395fc`"); tracker skill, Conflicts
Evidence:
- `origin/main` is `9fa1499`. It contains `3af8ddf tracker: prep R0210 Renumber step one (#33)`, with `tracker/rafts/R0210/R0210.md`, `check.sh`, `design-review-001.md`, `design-review-002.md` and `design-refute-001.md`. Each of these is an add/add conflict with this prep, and `tracker.sh list` fails on a duplicate id.
- The rounds in this directory (this file included) will have to move with the renumber, or `metrics` will mix two rafts' rounds.
- Main also gained R0090's specs (f0150-f0170, unit). I grepped them for guard names, `.cache`, `process.exec` and `user.email` and found nothing, but the "full gate passes jailed (638 passed)" figure predates them.
Critique: The fix is mechanical (`tracker.sh renumber R0210 <next free>`), but the longer it waits, the more files and prompt text carry the wrong id. The prompt for this raft will say "R0210" too.
Consequences: renumbering rewrites references in c0640 (`raft:`), in both check.sh files' comments and in the review/refute files. Prompts or worktree names already made must be re-made.
Recommendation: before the next prep commit, `git fetch origin main` and merge it. Then renumber this raft to the next free id from both trees (R0210 today), re-run the full gate jailed on the new base, and update the counts in Experiments and E14.

### F6 [low] Smaller gaps in the boundary
Where: as noted per item
Evidence and fixes:
- **Scan is case-sensitive, git config keys are not**: in scratch, `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/a git -c core.hookspath=/b config core.hooksPath` printed `/b`. A spec writing `-c core.hookspath=` switches the ref and push guards off, and gate case 6 doesn't see it. Fix: match `hookspath` case-insensitively (`string.lower(text)` against lowered names).
- **Fetch exception in specs mode**: only `check.sh` flows need it (`ci-verify.sh`). On Linux, where specs aren't jailed, it lets a spec move `refs/remotes/origin/*` in the real repository to fixture history. Fix: allow the fetch only when `PICKMAN_FENCE_NO_NETWORK_PUSH` is unset, with a case for each mode.
- **The jail protects the cwd's repository, not the inherited one**: a top-level run in a copy under `.cache` (c0470's AC5 pattern) finds no repository. It then denies only the copy, and the real checkout stays writable. That's harmless today, because AC5 fails before the tests stage, but the Audit sentence "the copy's own spec run is jailed" overstates it. Fix: the profile also denies each path in an inherited `PICKMAN_FENCE_REAL_GIT` and its parent checkout.
- **User-level git config**: `~/.gitconfig` carries the identity that every commit in every worktree uses, and the jail allows writing it. Fix: deny `$HOME/.gitconfig*` and `${XDG_CONFIG_HOME:-$HOME/.config}/git` in the jail (no spec uses `--global`), or name it in "Caught only by review".
- **Rollout**: `prep-tracker-hardening` and every other open worktree branch lack `scripts/lib/fence.sh`. Their Stop hooks keep running unguarded gates in the real worktree until they merge main, and they read their own, older skills. Fix: add a step to R0210's Order & dependencies: after landing, merge main into each open worktree branch before its next check, and list them.
- **Fixture rule vs the existing suite**: the testing skill now requires "check that `git rev-parse --show-toplevel` is the fixture before any git that writes". c0010, c0041, c0050, c0060, c0070, c0430, c0440, c0480 and `worktree-fetch` don't do that, so a code-mode reviewer touching them must flag them as high. Fix: say the check is required in specs that may run before the guards exist (acceptance specs of guard work), and is good practice elsewhere.

Verdict: changes
