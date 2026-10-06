# Review 001: c0067 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0067` (16 files), c0067.md, check.sh, acceptance specs, R0025.md, tracker and testing skills. `scripts/tracker.sh check c0067`: 13/13 PASS. The full gate was not rerun. The diff stays inside c0067's Touched modules (plus its own document); the ready.spec.luau:321 line and the c0081 allocate.spec branch rename are the authorized changes and are not findings. The `ready event` -> `ready_for_review` edit in the tracker skill is inside a Touched module and makes c0008 AC3 pass (verified).

Checked and found sound: publish move validation (all 8 rules; `from` and `path` are both `itemPath`s and `from` must exist on origin before any removal; published moves never touch `done/`; whole-directory rule; no second change inside a moved source directory; the diff-tree check counts `from` and `path` and nothing else may change; a removal can only name a validated `from`); `makeTree` removal and emptied-subtree dropping (`.gitkeep` siblings kept); `paths.rewrite` boundaries; `currentRaft` and its callers (commit, new --raft, activeRaft; stream worktrees never run `commit` or `new`); `cmd.ready` order (every readiness check and the build's own status check precede the push; the only earlier mutation is a fast-forward of the main checkout); the readied `start` path; `done`'s rewrite (prompt.md lives in the main checkout, so `git mv` in a worktree never carries it); the check.yml step (a non-raft ref yields no dirs and runs nothing); the pinned skill wording and the 13 banned phrases.

### F1 [medium] `sweepStale` deletes untracked, non-ignored work in the main checkout, and `sync` runs it with no clean check
Where: scripts/tracker/main.luau, `sweepStale` and `cmd.sync` (main-checkout branch).
Evidence: `sweepStale` empties any `tracker/{issues,rafts}[/active|/done]/<ID>` directory whose `<ID>/<ID>.md` is not in the index, using `git clean -ffdxq -- <dir>`. `-x` removes ignored files, and the untracked ones too. `cmd.sync` in the main checkout calls it after `pull --ff-only` with no `status --porcelain` check (only `ready` demands a clean tree). A new item directory (a new stub made by hand, a recovered `f0099/f0099.md`, an agent's stray write) that has not been `git add`ed is untracked, so the next `tracker.sh sync` in the main checkout deletes it and its files, and removes the empty directory. `-ff` also reaches nested git repositories under such a directory. The Design says "not tracked at `root`'s `HEAD`", but the code asks the index, not `HEAD`.
Critique: the point of the sweep is a stale duplicate: a directory an in-flight pull just emptied of tracked files and left holding ignored files (`prompt.md`, `.DS_Store`). The code removes far more than that, and it cannot be recovered from git. The tempting fix is to run it only when the tree is clean, but then `sync` in a dirty main checkout leaves the duplicate-id state this sweep exists to prevent.
Consequences: restrict the sweep to what it is for. Remove only ignored files (`git clean -fdX`, no `-x`, single `-f`) and only in a directory with no tracked file in it. When untracked, non-ignored files remain, leave the directory and print a one-line warning naming it. Use `git ls-tree -r HEAD --name-only -- <dir>` (HEAD, as the Design says) to decide "no tracked file". Keep never touching a directory that has tracked content. `ready` already refuses a dirty tree, so only `sync` and the later callers (stop, c0070's refresh) change behaviour: a leftover untracked file now keeps its directory, and the duplicate-id error then names it for the human.
Recommendation: make the change above. Spec cases: (a) an untracked non-ignored file in a stale directory survives `sync` and `sweepStale` prints a warning; (b) an untracked brand-new item directory (`c9999/c9999.md`) survives `sync`; (c) the existing prompt.md and `.DS_Store` cases still remove the directory; (d) a directory with a tracked document is untouched (existing).

### F2 [low] `docPath` and `idsOf` can be fooled by a nested id-shaped path, now that `paths` lists every item file
Where: scripts/tracker/main.luau `docPath` (suffix `/{id}/{id}.md`), `idsOf` (unanchored `/<ID>/<ID>.md$`).
Evidence: `tracker/issues/active/c0001/acceptance/c0002/c0002.md` is a valid `itemPath` (id c0001, rel `acceptance/c0002/c0002.md`), so it now enters `paths`. `docPath(paths, "c0002")` can return it, and `idsOf` counts c0002. Before this change `paths` held only documents and `check.sh` files, so this was impossible.
Critique: needs a contrived fixture today, but the number allocator and `moveOnOrigin` both consume these helpers.
Consequences: use `publish.itemPath(p)` and require `rel == id .. ".md"` in both; no behaviour change for real trees.
Recommendation: do that and add one spec case with a nested id-shaped file.

### F3 [low] A moved file is checked against a decoded read of origin, not against origin's blob
Where: scripts/tracker/publish.luau `validateMoves`, and the blob write (`hash-object --stdin` of `c.content`).
Evidence: "byte-equal" compares `c.content` with `read(from)`, and the same string is written. If `read` ever alters bytes (decoding, a filter), the moved blob silently differs from origin's, and the diff-tree check only shows the path as added.
Recommendation: for files that are not rewritten, compare `git rev-parse <base>:<from>` with the hash of the written blob (or reuse the object id in `mktree` directly). No new rule.

### F4 [low] A move may merge into a target directory that already holds other files
Where: validateMoves rule 3 is per path.
Evidence: if `tracker/issues/active/c0001/notes.txt` exists on origin while c0001 is moved in from the backlog, the move succeeds and the directory holds files of both. A tracked file with a name outside `[%w._-]` in a source directory makes every ready of that raft refuse (rule 6), with a reason that names the file.
Recommendation: also refuse when any origin file lies under a target directory that is not itself moved away in the same publish; keep rule 6's message.

### F5 [low] The ready-raft skill says `ready` enforces "the acceptance specs exist"
Where: .claude/skills/ready-raft/SKILL.md step 2.
Evidence: `cmd.ready` checks design, a check line, and `depends_on`; it does not check that the acceptance specs named in `check.sh` exist.
Recommendation: reword that bullet as the agent's own check ("confirm the acceptance specs exist"), or add the check to `ready`.

Verdict: changes
