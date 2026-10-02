# Review 006: R0210 (design mode)
Inputs: prep worktree `254438b` (R0210.md, R0210/check.sh, c0640.md + check.sh + fence/lock specs, c0650.md + check.sh + adapt.spec, c0660.md + check.sh + fixture/retrofit specs, design-review-001…005, design-refute-001…005); R0200's prepared files (`tracker/rafts/R0200/R0200.md`, `tracker/issues/c0510/**`, `tracker/issues/c0500/**`); prototype `proto2-c0640` `3527e0f` (`scripts/lib/fence.sh`, `scripts/lib/git-hooks/*`, `tests/lib/fixture.luau`, `tests/tooling/repo-fence.spec.luau`, `tests/run.luau`). Spot runs in the prototype, one spec file each: `adapt.spec` 5 passed, `fence.spec` 25 passed, and `git status` was clean afterwards. The git experiments ran only in scratch repositories under the session scratchpad. Nothing printed `REPOSITORY CHANGED`.
Dropped from design-review-005: F1, F2. Both refutations hold. The exception is now proven by probes, and the case breaks one condition at a time. AC10 covers the ancestor-in-ceiling run and the copy under `.cache`. The three `bash -c` blocks check the fixture and run with `cwd = repo`.

Summary: I found no new path by which a check writes the local repository. The jail, fence, lock and tripwire hold. The hook chaining resolves the repository correctly in the spot runs. c0660 only adds safety. The open problems are elsewhere:
- c0650 misses R0200's production code.
- c0650 adds a promoted spec that R0200 itself will turn red.
- On macOS, now that no hooks run under the jail, the "no network push from specs" guard can be bypassed.
- The new chaining is only partly tested, and so is the retrofit.

### F1 [high] c0650 leaves R0200's publisher (`scripts/tracker/publish.luau`, which uses `GIT_INDEX_FILE`) banned by the gate scan, and leaves R0200.md saying R0200 lands before the fence raft
Where: c0650 Design, "The allowlist" (two spec files only) and Touched modules; `tracker/rafts/R0200/R0200.md` Order & dependencies, the second bullet; c0510.md `commit` (the "private, uniquely named index file"); `tracker/issues/c0510/experiments/publish.luau.txt:132` (`local env = { GIT_INDEX_FILE = index }`); prototype `repo-fence.spec.luau:40-52` (`ALLOWED`)
Evidence:
- R0200's design builds its tree in a private index through `GIT_INDEX_FILE` in `scripts/tracker/publish.luau`. That file is under `scripts/`, which the gate scan covers.
- R0200.md says so directly: "the fence prep must exempt `scripts/tracker/publish.luau` and c0510's promoted specs … from that ban … **Open handoff**: that document still bans them today; its owner must make the change".
- c0650 allowlists only `tests/acceptance/c0510/commands.spec.luau` and `publish.spec.luau`. `adapt.spec`'s planted repository contains no publisher, so AC1 can't see the gap.
- When R0200 executes after R0210, its first gate run fails with `scripts/tracker/publish.luau names GIT_INDEX_FILE`. Its executor then has two ways out. Adding an allowlist entry to `repo-fence.spec.luau` weakens a guard, which the new review rule rates high. Redesigning a reviewed mechanism mid-raft is the other.
- R0200.md also still says "It lands before the repository-fence raft (the user's decision) … then c0510; then the fence raft executes", and it calls the fence raft R0190. c0650 reverses that order (`depends_on: [c0650]`) without touching R0200.md, so `/make-prompt R0200` would hand its executor two contradicting orders.
Critique: c0650's stated job is "R0200 … adapted, and wait for it", and R0200 names exactly what it needs. The tempting fix is one more `ALLOWED` row. Done blindly, that exempts a production file from the one ban that stops a script from pointing git at another index.
Consequences:
- **An allowlist row**: the reason must say why a private index can't reach the shared one. The path is built from `rev-parse --absolute-git-dir`, and the variable is passed per command, never exported. The row names a file that doesn't exist until R0200 runs, so the planted case must plant one to prove the row works.
- **A redesign**: R0200 builds the tree without an index (`git mktree`, fed from `ls-tree` plus `hash-object -w`), and no exemption is needed. That changes R0200's reviewed design, which is the user's call.
- **Either way**: the order reversal contradicts what R0200.md records as "the user's decision".
Recommendation:
- Put the choice, the allowlist row or the `mktree` redesign, and the order reversal to the user in R0210's report now.
- With the row:
  - add `["scripts/tracker/publish.luau"] = { GIT_INDEX_FILE = "<reason>" }`;
  - have `adapt :: planted …` also plant `scripts/tracker/publish.luau`, built from `c0510/experiments/publish.luau.txt`;
  - extend the allowlist-scope case to plant `GIT_DIR` in that file and expect `scripts/tracker/publish.luau names GIT_DIR`;
  - add a row A6, "the publisher not allowlisted", killed by the planted case.
- Add `tracker/rafts/R0200/R0200.md` and `tracker/issues/c0510/c0510.md` to c0650's Touched modules. Rewrite R0200's Order section: R0210 first, then c0650 adapts the specs and the publisher entry, then R0200. Remove the open handoff and the stale ids. Add a c0650 check that R0200.md no longer contains "lands before the repository-fence raft".

### F2 [high] c0650's promoted AC2 case turns the gate red the moment R0200 does what it was designed to do
Where: `c0650/acceptance/adapt.spec.luau`, case "R0200's c0041 replacement differs from the promoted c0041 only by R0200's own change"; c0650 Design item 3 ("R0200 copies this file over the promoted one")
Evidence:
- After `tracker.sh done`, `adapt.spec` runs in every full gate. The case compares `strip(replacement)` against the promoted c0041 **as it is on disk**.
- When R0200 executes, it copies the replacement over `tests/acceptance/c0041/worktree.spec.luau`, and its AC8 `cmp`s them. After that, promoted equals replacement, which still contains `PICKMAN_PUBLISH`, while the stripped replacement does not.
- I reproduced this with the spec's own strip patterns on the prototype's files, in a scratchpad Lune script: today `true`, after R0200 copies `false`.
- `located("c0510")` then finds `done/c0510/replacements/`, so the case reads the file and fails. It doesn't error out.
- Neither R0200's `depends_on` nor its Overrides name `tests/acceptance/c0650/adapt.spec.luau`. R0200's executor would hit a red sequestered spec it may not edit.
- Later, any chore that edits c0041 after R0200 also makes the stale `done/` replacement disagree.
Critique: a promoted spec must keep holding once the work it guards is finished. This one pins a state that lasts only until R0200 runs. The tempting fix, comparing `strip(replacement)` with `strip(promoted)`, survives R0200's copy. It still goes red at the next edit to c0041.
Consequences: the invariant is only meaningful while c0510 is not done. After that, R0200's AC8 has done the comparison, and the gate scan keeps c0041 clean of `GIT_CONFIG_`.
Recommendation:
- Make the comparison a function `matches(replacement, promoted)`.
- In the case, run it only while `located("c0510")` is not under `done/`. Once it is, assert only that the promoted c0041 names no `GIT_CONFIG_`, or that the replacement file is no longer needed.
- Add a case that feeds the function directly:
  - `(R, R)` with c0510 done passes;
  - `(R with the gc override, promoted)` fails;
  - `(R, promoted)` passes.
- Add the row A7 "unconditional comparison after R0200", killed by that case.

### F3 [medium] On macOS (every jailed run) the "no network push" guard is just a `pushInsteadOf` rewrite, which an uppercase scheme, an explicit `pushurl` or an `insteadOf` alias bypasses. AC2 says "by any URL form"
Where: c0640 Design, Environment guards items 7-8; AC2; Rules row N7 (`reasoned`); `repo-fence :: specs have no GitHub credentials …` (prototype checks only that the three config entries exist); fence.spec `github` probe (runs nested, where the hooks are set)
Evidence:
- Under the jail, no `pre-push` is set any more. In a scratch repository with the guard's injected entries (`pushInsteadOf` for https/http/git, an empty `credential.helper`, `GIT_TERMINAL_PROMPT=0`):
  - `git push https://example.invalid/x` was rewritten: `'/nonexistent/pickman-fence-no-networkexample.invalid/x' does not appear to be a git repository`;
  - `git push HTTPS://example.invalid/x` and `Https://…` went to the network: `Could not resolve host: example.invalid`. macOS's case-insensitive file system finds `git-remote-https`;
  - a remote with `pushurl = https://example.invalid/y` reached the network: `pushInsteadOf` never applies to an explicit `pushurl`;
  - `-c url.https://example.invalid/.insteadOf=foo:` followed by `git push foo:z` reached the network as well.
- With credentials removed, GitHub still rejects these pushes. Credentials can still come from places the guard doesn't clear: `~/.netrc` (git's curl uses it), `http.extraHeader` in the global config, or a URL that carries them.
- No case runs an actual push on the jailed path. The `github` probe runs nested, where `pre-push` catches everything, and repo-fence case 5 only reads the config entries.
Critique: before this round, `pre-push` refused every non-local URL in specs everywhere. Dropping hooks under the jail for speed (E25) quietly weakened that on the main platform, and AC2's claim is now false there. The tempting fix, adding more `pushInsteadOf` prefixes, can't cover `pushurl` or aliases.
Consequences:
- `protocol.allow=never` with `protocol.file.allow=always` blocks every non-local transport, by any spelling and after any rewrite, for push, fetch and clone, with no process start. I checked it in the same scratch repository:
  - `transport 'https' not allowed` and `transport 'HTTPS' not allowed`, for the `pushurl` remote and for the alias too;
  - a relative and a `file://` push into a local bare repository still worked, and so did a local clone.
- It also stops a spec from fetching off the network, which matches "a spec never reaches the network".
- The ssh message changes from the fence's `refused` to `transport 'ssh' not allowed`, so the `git ls-remote git@example.invalid:x.git` assertions (repo-fence case 5 and the `github` probe) must accept either message.
- A spec could override the setting with `-c protocol.allow=always`, so the scan should forbid `protocol.allow`.
Recommendation:
- In specs mode, inject `protocol.allow=never` and `protocol.file.allow=always`. The `pushInsteadOf` entries can stay or go.
- Add `protocol.allow` to the scan's names.
- In `repo-fence` case 5, which runs top-level and jailed in the gate, push from a fixture under `.cache` to `HTTPS://example.invalid/x` and to a remote whose `pushurl` is `https://example.invalid/y`. Both must fail with `not allowed`, which also means no DNS lookup happened.
- Make row N7 `run`, and add N8 "rewrite only (no protocol block)", killed by that case.
- Add `~/.netrc` and `http.extraHeader` to the testing skill's list of what credential removal doesn't cover.

### F4 [medium] The chaining that c0510 actually needs, the `pre-push` guard handing off to a fixture's own `pre-push`, is unchecked, and so is exit-code propagation
Where: c0640 Design item 7; AC2 ("the guard hooks chain to a fixture's own"); fence.spec `ownhooks` probe; Rules row C1; E24
Evidence:
- The `ownhooks` probe checks a `pre-commit` stub (a log file appears) and the `reference-transaction` chain (a ref line in the log).
- It never pushes with a fixture `pre-push` in place, and it never installs a failing hook. So these mutants pass every c0640 check:
  - **C2**: `pre-push` ends in `exit 0` instead of `chain "$@"`;
  - **C3**: the stub runs `"$own" "$@"; exit 0`;
  - **C4**: the guard reads stdin before it chains, so the fixture's hook gets no ref lines.
- E24 says c0510's specs write `.git/hooks/pre-push` to stage push races. On macOS those specs run jailed with no hooks, so they pass natively. The gap first shows on Linux CI after R0200 lands, as a red sequestered c0510 spec far from its cause.
Critique: the chaining was added for c0510's `pre-push`, and that is the one hook its spec case leaves out.
Consequences: none beyond probe lines. The nested inner run already has the hooks.
Recommendation: extend the `ownhooks` probe:
- install a fixture `pre-push` that writes its arguments and stdin to a log, then push the fixture into a local bare fixture. The push succeeds, and the log holds the remote name and a `refs/heads/` line;
- install a `pre-commit` that exits 1. The commit fails, and HEAD is unchanged.

Add rows C2, C3 and C4, all `run`, and keep the case name so AC2 doesn't change.

### F5 [medium] c0660: nothing dynamic catches a missed write path, and the static scan that does has blind spots
Where: c0660 Rules row "retrofitted specs leave the repository untouched even without the guards | AC4 | a retrofit that misses a write path"; `retrofit.spec.luau` `violations`; c0660 AC4 (`unguarded`)
Evidence:
- **AC4 can't kill that row's mutant**. In a normal run every fixture exists, so a raw `process.exec("git", {"commit", …}, {cwd = fx})` left in a spec behaves exactly like `fixture.git(fx, …)`. The clone's snapshot is unchanged either way. Only the scan can catch it.
- **The scan misses**:
  - git inside a shell string: `process.exec("sh", { "-c", "cd " .. fx .. " && git commit …" })` names neither `"git"` nor `tracker.sh` as the command;
  - a renamed module: `local proc = require("@lune/process"); proc.exec("git", { "commit" })`, or `Process.exec`, since the pattern is the literal, case-sensitive `process%.exec`;
  - `process.create`;
  - redirecting arguments through the helper: `fixture.git(fx, { "-C", other, "commit" })` or `--git-dir`/`--work-tree`. The check passes for `fx`, then git runs in `other`, and with `other`'s repository missing, upward. That is the incident's mechanism.
- **AC4 runs with checks-mode credentials**. It runs inside `check.sh`, so the unguarded suite inherits `GH_TOKEN`/`GITHUB_TOKEN`/`SSH_AUTH_SOCK` and the real `gh`. Three of the twelve rely on a fake `gh` on `PATH`. Low risk, because the clone has no GitHub remote, but specs never otherwise run with credentials.
Critique: the row claims a dynamic proof that AC4 doesn't give, so a reviewer of the retrofit may trust AC4 and skim the diff.
Consequences: a wider scan may flag legitimate `sh -c` calls (c0330's `ac.sh` scripts, c0041's hook runs). These either go through `fixture.exec`, or carry no `git`/`tracker.sh` text.
Recommendation:
- Point the row at `retrofit :: no listed spec runs git …`. Keep AC4 for "the twelve still pass without the runner's guards".
- Extend `violations`, each with a self-test line:
  - any `.exec(` or `.create(` whose receiver isn't `fixture` is checked like `process.exec`;
  - a string argument containing `git ` or `tracker.sh` passed to `sh`/`bash` with `-c`, outside `fixture.exec`;
  - `"-C"`, `"--git-dir"` or `"--work-tree"` anywhere in these files.

  Raise the self-test's expected count to match.
- In AC4, run the suite through `env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN -u SSH_AUTH_SOCK`. `env -u` is allowed by the scan.

### F6 [low] Document and interface gaps
Where and fix:
- **c0640 Design, Environment guards**:
  - the list loses item 7's number (the line starts `. **Hooks only…`);
  - the signature block shows only `pickman_fence <checkout> [specs]`. The prototype decides the hooks from a third argument (`pickman_fence <checkout> specs [<jail>]`), which Run guards step 4 doesn't pass either. Without it, an executor working from the document can't tell how `fence.sh` knows it is jailed. Add the argument to both places, and say it comes from the jail decision, never from an inherited variable;
  - R0210's diagram still lists the hooks with no "only when not jailed".
- **Gate spec Exempt list**: it omits `scripts/lib/git-hooks/.repo.sh`, which the prototype exempts (it names `GIT_DIR`). The extensionless hook files, `pre-push` among them (which names `GIT_DIR` through `env -u`), aren't scanned at all, because only `.luau` and `.sh` are. Say both, so the review knows to read that directory by hand (Repository safety).
- **c0660 AC4's Perl**: it removes exactly the line `require("./lib/fence").enter()`, and c0640 only says "`tests/run.luau` calls `fence.enter()`". Pin that literal line in c0640's Run guards, or an executor who writes `local fence = require(…)` fails c0660 AC4 and has to escalate. It fails closed, so this costs time, not safety.
- **`fixture.check`** accepts a repository under any `/.cache/` folder, `~/.cache/…` included. It refuses the real checkout only because that checkout isn't under such a folder. Say so in the testing skill, or require the spec's own `<root>/.cache/`.
- **c0660 Design** says later cases refuse when setup didn't finish ("c0640's `setUp()` pattern"), but neither `retrofit.spec` nor any row checks it. Mark it Judged-free review guidance, or drop the sentence.
- **c0650 AC4** passes on any mention of "allowlist" in the testing skill. Also grep for "Repository safety", or for the per-file and per-name wording.

Verdict: changes
