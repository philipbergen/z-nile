# Refute 001: f0427 and f0428 (design mode)
Answers `design-review-001.md`. Each answer follows the lead's decision on that finding, and each decision is recorded as a guess the owner can overrule (f0427 `guesses.md` G3 to G5 and G8 to G14; f0428 `guesses.md` G3, G4 and G7 to G9). Problem, Non-goals and Solution are unchanged. Where a finding needs a captured sentence changed, the question is in "Open to the human" as S1 or S2. One new experiment ran (E14), and E15 is the program inventory. No spec or gate was run.

- F1: fixed. f0427 Design section 5 (G8):
  - Go writes the host facts (the raft branch's tip and base, each layer's sha range and patch-ids, the PR's state, merge commit, head and review decision from `gh --repo <upstream>`, and the gate result for the head sha) into `ZN_HOST_FACTS`.
  - Under `ZN_HOST`, `workread` (:819-860, `prLookup` at :627-650) and the eight `gh pr` calls read the facts instead of the tracker's refs.
  - A layer's diff is `git -C <host> diff <first>^..<last>`.
  - Reviews, final reviews, traces and the harvest are written in `.tracker/.worktree/<R-id>` and published by plumbing. A trace cites `<host sha>:<path>:<line>`, which `trace --check` reads with `git -C <host> show`.

  Consequences: this is the one engine step (implementation step 8), and it runs pickman's full gate once.
- F2: fixed. Section 6 (G9): `zn done --check` runs the whole refusal list of main.luau:5409-5470. Both `zn land` and a `zn pr` to a repository the `gh` user does not own call it first. The gate result is a tracker record keyed by host sha (section 8 step 4). None of our reviews, traces or guesses are posted upstream. AC12 and `donecheck.spec`.
- F3: fixed. Section 3 lists the wrapper's duties: `ZN_TOP` and `ZN_CWD`, the CPU limit (lowered only), `work` rerouting, and `approve`'s gate. The gate is an ioctl test of stdin, so `zn approve </dev/null` refuses, and so do runs under `ZN_DISPATCH` and `ZN_APPROVE_SESSION`. The engine's test at :6146 stays as the second line. AC6 and `frontdoor.spec`.
- F4: fixed. Section 7 (G10): `ready_commit` is published after `ready`. Gate and `done --check` read `check.sh` and `acceptance/` from that commit. `zn tracker merge` and the standing worktree's publish guard refuse any change to `check.sh`, `acceptance/**` or `approval.md` of a ready or active item; `approve`'s own row is the one exception. AC11 and `sequester.spec`.
- F5: fixed, and G4 is replaced. The old evidence ("one perl call") was wrong. E15 inventories every program; perl has 11 direct call sites plus the scripts, matching the review's list. The first packaging requires `bash`, `perl` and `uuidgen`, and says so (section 4); `zn doctor` checks all three. `hostname` gets a shim, because Arch base lacks it (inetutils). `lsof`, `security`, `getconf` and the macOS tools are only on paths that are off in host mode. The Solution's sentence on the only programs is scope question S1. AC8 and `doctor.spec`.
- F6: fixed. Both tickets now have a Test plan (one sequestered spec per criterion), a Rules and mutants table (16 rows in f0427, 13 in f0428), and real `check.sh` lines, one per checked criterion (15 and 10). Overrides is `none`: `lune run z-nile/affected` over f0427's engine paths selects 310 specs, all kept unchanged because every engine change is behind `ZN_HOST`, and the new paths select none. The spec files themselves are written at the start of their implementation step and must fail first. The mutants are `reasoned`, because there is no code to mutate yet.
- F7: fixed, with G11. A raft is one host branch `zn/<R-id>-<slug>` and one pull request. Each ticket is a layer, a commit range, and dependent rafts stack in the fork (f0427 section 5, f0428 "A raft's host branch"). f0428's Solution says one branch per ticket, so the change of word from "ticket" to "raft" is f0428 S1.
- F8: fixed, with G12. The delivery ends in the named stage "pull request open, waiting on upstream". `zn work` reads the PR's state on each run: merged, by any method including squash (`state: MERGED`), publishes landed; closed frees the claim; changes requested goes back to code; a head newer than the approved one goes back to review. f0427 AC14 and `prstate.spec`.
- F9: fixed, with f0428 G8. There is no local owed state. Each case the review named:
  - Spend rows are keyed by (ticket, patch-id), so a rebase keeps them.
  - `land` asks the PR's state first, so a publish that failed after the merge is redone once.
  - An owed row after the session ends is derived again on the next run.
  - "ready won, then the fetch failed" means `worktree` is simply run again.
  - A scan refusal exits 5 and is never retried as a race.

  f0428 AC10 and `recover.spec`.
- F10: fixed, with f0428 G3. `zn scan` runs as `pre-commit`, inside every plumbing publish (`commit-tree` runs no hook) and at `pre-push`. It checks content, commit messages and file names for: this machine's `$HOME`, host path, machine name and user; every home path seen by this tracker's machines; GitHub tokens; and private keys. The author email gets a warning (Q8). `zn doctor` fails on `core.hooksPath` or a hook that is missing or not zn's. The 379 home paths in pickman's tracker prose belong to pickman's own trackers, whose move is a Non-goal of f0428. AC8.
- F11: fixed, with f0428 G9. Resolution walks up from the working folder: a tracker checkout or worktree leads to its host. The tracker-side verbs are `zn tracker worktree` and `zn tracker merge`, and `worktree`, `commit`, `pr` and `land` are the host's alone. "land" now means only the implementation merge. f0428 AC3.
- F12: fixed, with G13. The design now makes the tree match the engine instead of switching paths:
  - ignored links `z-nile/{engine,lib,vendor,templates,roots.luau,affected.luau}` into the cache, so `ac.sh`, `roots`, the fence, `measure.pl`, `bounded.pl` and the four `lune` spawns resolve;
  - `lune`, `zn` and `hostname` shims on PATH, so `approvewalk`'s re-run works;
  - plumbing from a standing tracker worktree.

  E14 published `new` this way with no engine change. `ZN_HOST` covers only behaviour: the host facts, done refusing, the watch net (:2857, :4945), `reap` (:8729) and `dispatch` off, and the skill links. The 355 `./zn` messages stay; the host skill maps `./zn` to `zn`. Section 8 defines the host `check.sh` template, its acceptance shape and `zz-host-test`.
- F13: fixed. Section 8:
  - `test.command` and each `check.sh` run through the bounded runner with `[test] seconds`.
  - The host's refs and config are snapshotted before and after, and any change outside the allowed list fails the gate.
  - The first use on this machine of a `test.command` or `check.sh` hash, which may come from the public tracker, needs one confirmation typed in a terminal, kept in `.tracker/.cache/trusted`.

  There is still no jail on Linux, and the design says so. AC10.
- F14: fixed. Section 1: the sha256 of `lune` and the manifest is checked on every run, and a mismatch or a missing file re-extracts. The cache folders are 0700 and a symlink in the path is refused. `XDG_CACHE_HOME` is used only when it is absolute and owned by the user. An exec failure on `noexec` names `ZN_CACHE`. AC3.
- F15: fixed, with f0428 G4. Remotes are stored as host plus owner/repo, normalised from ssh, scp-like and https forms. A URL holding credentials is refused. `--upstream` covers `gh repo fork`'s origin/upstream naming. f0428 AC2 and AC9.
- F16: fixed, with G14. Section 10: `zn live` is in the same binary, with its state in `.tracker/.cache/live`, and `where.MainCheckout` is fed by the front door. The tracker records `zn_version`, and an older binary refuses. `zn init --upgrade` rewrites the skills. No pickman lesson ships.
- F17: fixed. Step 1 cross-builds linux/amd64 and proves AC1 on an ubuntu runner (`zn-linux.yml`, AC2). OC0 (step 6) has the owner run a development build on Omarchy right after the tracker commands work, and release packaging comes after it (step 12). Every step names its criteria. Steps 1 to 7 touch no engine file, so only step 8 needs pickman's full gate.
- F18: fixed. Section 9 lists every guarantee of `bounded.pl` for the Go port: defaults and caps, CPU limit only lowered, own process group, the watchdog pipe, TERM then KILL after 2 s, the group sweep, exits 123, 124, 125 and 2, `ZN_BOUNDED_DEADLINE`, `--report` and `ZN_MEASURE_*`. Rows are in the mutants table, plus AC9.
- F19: fixed, with G3. The bare origin is in `$XDG_DATA_HOME/zn/trackers/<host id>.git`. The Solution sentence "every … under `.tracker/`" is scope question S2.
- F20: fixed, with G5. There is one source: z-nile's skills with marked `host` and `pickman` blocks. The build generates the host edition, checks it for staleness and writes a manifest, and no criterion names a count. AC7.
- F21: fixed. AC4 is now AC7's "no file under `.claude/` is newer than the marker". The board criterion (AC15) uses the stages idea, design, bundle, code, review, approval, landed.
- F22: fixed. f0427's `init` appends only `.tracker/` and `.worktree/`; zn writes nothing in the host's `.cache/`. f0428 adds `.cache/`, as its Solution says.
- F23: fixed. f0428's `init` refuses a submodule, a separate git dir and a bare host with worktrees, naming each. f0427 section 12 does the same. f0428 AC2.
- F24: fixed. Section 3: `.tracker/.models.toml`'s `[rounds]` and the work profile carry the review-round counts, and the front door passes them through unchanged, so how many rounds a raft costs is the owner's setting.

The reviewer's ten questions for the owner were not in the text pasted to this answer. Each ticket's "Open to the human" holds the questions this round raised, without duplicates, and the reviewer's ten must be merged into it when available.
