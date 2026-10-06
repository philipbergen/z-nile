# Review 002: c0072 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0072` (main.luau `cmd.land`, `captureScope`, `frontKeys`; the make-issue and tracker skills; c0072.md), round 1 (`stream-review-c0072-001.md`, `stream-refute-c0072-001.md`). `scripts/tracker.sh check c0072`: 5/5. Attacks ran in a throwaway fixture under the session scratchpad (fresh `git init` seed with the tooling copied in as land.spec does, bare origin, main clone, second clone, capture worktrees); the real repository was not touched.
Dropped from review-001: F1, F2, F3, F4, F5, F7 (fixed, verified below); F6 (refutation accepted).

Rulings on the round-1 answers:
- F1: accepted, and reproduced. Gate script that pushes a non-overlapping edit to the same issue from the second clone and then runs `git fetch origin main` in the land worktree: the first push was refused (non-fast-forward), land re-merged, re-gated and pushed; `main`'s tree has the other clone's edit, the capture's edit, and the history is linear. With an overlapping edit the re-merge conflicts, land aborts the merge and tells the author to resolve; the other push is intact on `main`. Nothing is reverted.
- F2: accepted. Refused, each with the key named: changed `raft:`, `slug:`, `type:`, `emergent:`, `created:`, `design:`, `status:`; a key added (`foo:`), a key removed, a key renamed (`Slug:`, `raft :`), an `id:` that mismatches the directory.
- F3: accepted. A duplicate key (a second `slug:`, a second `raft:`, a second `emergent:`) is refused.
- F4: accepted. `chmod +x` is refused (mode 100644 required).
- F5: accepted with one residue (F1 below).
- F6: accepted (sequestered, stale name only).
- F7: accepted. A blank override counts as unset; the override is named on the `gate:` line before the run.
Legitimate captures still land: a body edit, a `title:` change, a `depends_on:` edit (each pushed as one commit).

### F1 [low] Landing step 3 says a capture the user did not ask for "is not landed without asking", which contradicts make-issue step 6
Where: `.claude/skills/tracker/SKILL.md` Landing a change step 3, last two sentences.
Evidence: make-issue step 6 tells the agent to run `tracker.sh land` as the last step of every capture, with no question; step 3 then says a capture the user did not ask for is not landed without asking. A capture is always the user's request, so the sentence never applies, and it reads as a reason to stop before `land`.
Critique: harmless in practice, but an agent can read it as a question gate. Tempting fix: delete the sentence, which is right.
Consequences: none; the parenthesis "(A capture has no PR: ...)" then stands alone and is enough.
Recommendation: drop "and a capture they didn't ask for is not landed without asking" from step 3.

### F2 [low] A `---` line inserted after the last frontmatter key moves the frontmatter boundary and lets text through as "body"
Where: `captureScope` / `frontKeys` (`^---\n(.-)\n---`, same pattern as `store`'s readers).
Evidence: inserting `---` and `raft: R0010` after `status:` landed: the original frontmatter is unchanged, and the new `raft:` line sits in the body between two `---` lines. Every reader in the tracker uses the same lazy pattern, so none reads it as frontmatter.
Critique: not an exploit with today's readers, and a capture may edit the body freely. Noted so the rule "frontmatter unchanged" is understood as "the first block".
Recommendation: none required.

Verdict: approve
