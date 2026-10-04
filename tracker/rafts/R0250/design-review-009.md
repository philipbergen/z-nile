# Review 009: R0250 (design mode)
Inputs: prep-ready-raft at 7200c58. Read: `design-review-008.md` and `design-refute-008.md`; the c0780 and c0790 documents, `check.sh` files and acceptance specs (diff 0c1a0b2..7200c58); `scripts/tracker/publish.luau` (`publish.allowed`), `scripts/tracker/store.luau` (`store.find`); `tracker/templates/issue/doc.md`; c0660's `@tests/lib/fixture` API. Ran `land.spec.luau` in a `$TMPDIR` clone of 7200c58, with a pass-through stand-in for `@tests/lib/fixture` (R0210 hasn't landed it yet). In `refused`, the `land` call was replaced by printing `git diff --name-status --no-renames origin/main HEAD` and both copies' `design:`/`status:` after land's own fetch and merge.

Checked against refute 008:
- **F1 (path rule)**: fixed. On the fixture, the R0900 sub-case's diff is `M tracker/issues/<id>/<id>.md` plus `M tracker/rafts/R0900/R0900.md` (draft on both sides, no `status:` on either). The template sub-case's diff is the same shape, with `M tracker/templates/issue/doc.md`. `publish.allowed` accepts `tracker/rafts/R0900/R0900.md` (`kind == "rafts"`, `file == "R0900.md"`), so the reuse mutant lands it, and the spec kills that mutant. The frontmatter-decides mutant lands the template, and the spec kills that one too.
- **F2 (demotion)**: fixed. The diff shows f0600 going from `design: ready`/`status: prepared-a-b-c` on origin to `design: draft` with the same status. Only a check of origin's copy refuses it, so the new-copy-only mutant is killed. The plain-edit sub-case (ready on both sides) still kills the origin-only mutant, together with self-promotion.
- **F3**: fixed. `history.spec` line 143 asserts that c0040 has no spells, and the Rules row is there.
- **F4**: fixed. The Design rewords the bullet as a whole, scoping the status-only clause to status publishes, keeping it on one line with `tracker-only`, and AC5's grep still finds `tracker.sh land`.
- **Fixture state per reset**: correct in all eleven sub-cases. Land's merge prints `Already up to date.` every time. After each `reset --hard HEAD~1`, `status --porcelain --untracked-files=all` is empty and HEAD is the same capture commit. Each sub-case's diff holds only the capture's own clean `M` (draft→draft, same status) plus the offending path, so each one fails only for its stated rule. In the c0980 case, `c0980.md` sorts before `check.sh`.

### F1 [high] The fixture documents f0500, f0600 and R0900 have no `slug:`, so every `tracker.sh new issue` after the "merges what others pushed" case fails, and land.spec can't pass with any implementation
Where: `land.spec.luau:118` (f0500), `:147` (f0600), `:152` (R0900); `scripts/tracker/store.luau:79-82` (`store.find` raises `<doc> has no slug: in its frontmatter`)
Evidence:
- Run against 7200c58's tooling (stand-in fixture helper, `land` missing): the "merges what others pushed…" case pushes `tracker/issues/f0500/f0500.md` as `---\nid: f0500\ntype: feature\ntitle: Elsewhere\n---\n`. Every later `capture(...)` then fails inside `tracker.sh new issue`:
  - `refuses a change outside…`: `tracker new: tracker/issues/f0500/f0500.md has no slug: in its frontmatter; add slug: <kebab-case-words>`;
  - `refuses anything but…`, `refuses when the gate fails`, `retries a lost race`: the same error, naming `tracker/issues/f0600/f0600.md`.
- These cases fail before land is called, so no `cmd.land` can turn them green. AC1–AC4 are all unpassable as written.
- With `slug:` added to the three documents (`elsewhere`, `ready`, `draft-raft`), every capture succeeds. Each sub-case then reaches land in the state described above, and R0900 without a `status:` line doesn't trip `new` or `worktree`.
- None of c0730–c0760 or c0680 (which run before c0780) drops the slug requirement. Their documents mention `slug` only in their own frontmatter.
Critique: the tempting fix is to make `new` tolerate a missing slug, or to have land's executor "fix the spec". The first changes unrelated tracker behavior. The second is forbidden, because the spec is sequestered once execution starts. So prep has to fix it now.
Consequences: every hand-written tracker document in a fixture that `tracker.sh` will later scan needs `slug:`, raft documents included (`store.find` checks both kinds). The prep can't run this spec until R0210 lands `@tests/lib/fixture`. That is how this went unseen for several rounds, and the next fixture edit can hit the same thing.
Recommendation:
- Add `slug: elsewhere` to f0500, `slug: ready` to f0600 and `slug: draft-raft` to R0900 in `land.spec.luau`.
- Record in c0780's Unknowns & experiments that the spec's setup and capture steps were run against current tooling with a pass-through stand-in for `@tests/lib/fixture`, and that every case reached `tracker.sh land`.
- No spec case or user decision is needed beyond this.

Verdict: changes
