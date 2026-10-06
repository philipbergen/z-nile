# Review 001: c0072 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0072` (main.luau, make-issue and tracker skills, c0072.md), c0072.md Design and Rules and mutants, `check.sh`, `acceptance/land.spec.luau`, the tracker and testing skills, R0025 Wording. `scripts/tracker.sh check c0072`: 5/5. Banned phrases: none of the 13 in the changed files. Diff scope: only c0072's Touched modules and its document (the spec is already in the worktree). Attacks were run against a throwaway fixture (bare origin, clone and capture worktree under the session scratchpad, `PICKMAN_LAND_GATE` set); the real repository was not touched.

Attacks that were refused correctly: rename (with `--no-renames` it shows as D plus A), symlink (T), extra path segment, a raft or template document, a `design: ready` or frontmatter-less or CRLF document (design is not read as draft), a second `status:` line after the real one, a failing gate (`false`, `exit 3`, a quoted command), nothing to land, and the retry-after-race case in the spec.

### F1 [high] The commit's parent is re-resolved after the gate, so a fetch inside the window silently reverts others' pushes
Where: `scripts/tracker/main.luau` `cmd.land`, `local parent = sh.git({ "rev-parse", "origin/main" })` (after the gate), together with `refuseStale()` (it runs `git fetch origin main`) between the merge and the scope diff, and the gate itself.
Evidence: in the fixture, the gate command pushed another commit to origin (it appended a line to c0010) and ran `git fetch origin main` in the capture worktree, as a gate that fetches would. `land` then took `parent = origin/main` (the new tip), built `commit-tree HEAD^{tree}` (a tree that lacks the other commit), and pushed it as an ordinary fast-forward. Result on `origin/main`: the other commit is in history, but its change is gone from the tree (`git show main:tracker/issues/c0010/c0010.md | grep -c "other edit"` printed 0). The same happens with no gate at all when another push lands between the merge and the fetch inside `refuseStale()`, which then also moves the diff base. `fence.sh` itself says check.sh flows "may still fetch into refs/remotes/", so a real full gate can do this. The spec's race case only pushes from another clone and never fetches in the worktree, so it can't see this.
Critique: Design step 5 says the commit is made on top of "the `origin/main` that was just fetched", but the code uses whatever `origin/main` is at commit time. The tempting fix is to re-merge after the gate; that changes what the gate checked.
Consequences: the base sha must be pinned once per try: `base = rev-parse origin/main` straight after the fetch (and after `refuseStale`, or with `refuseStale` moved before the fetch), `git merge base`, `git diff base HEAD`, `commit-tree -p base`. After a failed push, compare the fetched `origin/main` with `base` for the race test. Then a fetch during the gate only makes the push non-fast-forward, which already goes to the retry path, and the retry merges the new tip. The tree gated is the tree pushed.
Recommendation: pin `base` as above. Add a spec case where the gate script pushes from another clone and then fetches into the worktree, and assert the other commit's change is still in `main`'s tree (the spec is sequestered: the author must escalate this addition to the lead).

### F2 [medium] The scope check ignores every frontmatter key except `design:` and `status:`
Where: `captureScope`, `frontOf` comparisons only.
Evidence: in the fixture these capture commits were pushed: an `<ID>.md` overwritten with another issue's text (c0020.md now says `id: c0010`, so two documents claim one id); a `raft: R0010` and `depends_on: [c0010]` added to a draft issue (it joins a raft with no claim and no status stamp); `slug:` rewritten. All are `M`, draft on both sides, status unchanged.
Critique: the Design states the rule as "design draft on both sides, status unchanged", so this follows the Design, but the scope check is the only gate on a direct push and `raft:`, `id:`, `type:`, `slug:` and `depends_on:` are not capture content (a capture edits the Problem, Non-goals and Solution ideas, per make-issue).
Consequences: comparing those keys needs a rule for what a capture may change in frontmatter: `title:` yes, everything else no. A capture that legitimately fixes a typo in `slug:` goes through a PR instead.
Recommendation: refuse unless `id`, `type`, `slug`, `raft`, `depends_on`, `emergent`, `created`, `status` and `design` are equal on both sides, and `id` equals the directory name. Spec cases: a changed `raft:`, a mismatched `id:`.

### F3 [medium] `frontOf` reads the last duplicate key; `store.withFront` and any first-match reader use the first
Where: `captureScope` (via `frontOf`), against `scripts/tracker/store.luau` `withFront` (`gsub(..., 1)` replaces the first match).
Evidence: a capture inserted `design: ready` above `design: draft` and `status: active-x-y-z` above the real `status:` line; both were pushed. `frontOf` sees draft and the unchanged status; the first-match writer sees the opposite. The refused cases (second `status:` after the real one) only work because last-wins sees the change.
Critique: the "status unchanged, design stays draft" rule can be sidestepped, and a later `tracker.sh status` or design flip edits the line the readers ignore.
Consequences: a duplicate-key rule is needed.
Recommendation: refuse a document where `design:` or `status:` (better, any frontmatter key) appears more than once on either side, and compare the whole frontmatter block as in F2. Spec case: a duplicate `design:` line placed first.

### F4 [low] A mode change on an issue document passes
Where: `captureScope` (`--name-status` has no mode information).
Evidence: `chmod +x tracker/issues/c0030/c0030.md` was pushed as an `M`.
Critique: harmless today, but the Design says "every line must be an `M` of exactly" the document; a mode change is not an edit of its text.
Recommendation: compare modes (`git diff --raw` shows `100644 100644`), or refuse when the old and new modes differ; one spec case.

### F5 [low] Tracker skill wording: Landing step 3 and the exception bullet are clumsy and step 3 now contradicts itself
Where: `.claude/skills/tracker/SKILL.md`, Landing a change step 3 and the direct-push exception bullet.
Evidence: step 3 reads "**Merge** (a capture has no PR: `tracker.sh land` in step 2 already pushed it) only when the conditions under Merging hold ... Prep or capture that the user didn't ask for is not merged without asking." A capture is now landed in step 2 by `land` with no question, so the last sentence no longer fits captures, and "only when the conditions under Merging hold" (green CI, a PR) can't apply. The exception bullet has "(`tracker.sh`'s status publishes)", which is hard to parse.
Recommendation: step 2: "A capture lands with `tracker.sh land` (no PR) and skips steps 3 and 4: `land` prints its own cleanup command"; step 3: "Merge (not for a capture) ...; prep that the user didn't ask for is not merged without asking"; the bullet: "an existing document only in its `status:` line (the status publishes of `tracker.sh`)". Keep `tracker-only` and `tracker.sh land` on the one line (the AC5 grep), and keep the Worktrees row as is.

### F6 [low] Spec and comment name `c0780`, not `c0072`
Where: `acceptance/land.spec.luau` header and `.cache/c0780-land`.
Evidence: the spec says "c0780: `tracker.sh land` ..." and writes its fixture under `.cache/c0780-land`; this issue is c0072, and `check.sh` points at `c0072/acceptance`.
Recommendation: note only; the spec is sequestered, so rename it only if the lead escalates other changes to it (F1).

### F7 [low] `PICKMAN_LAND_GATE` that is blank or whitespace-only passes the gate
Where: `cmd.land`, `override ~= ""`.
Evidence: `PICKMAN_LAND_GATE="  "` ran `bash -c "  "`, exited 0, and pushed. It is announced only after the push ("gate overridden"), and the override is an environment variable that can leak from a shell profile.
Recommendation: trim before the emptiness test, and print `gate (overridden): <command>` before the run instead of only after the push.

Verdict: changes
