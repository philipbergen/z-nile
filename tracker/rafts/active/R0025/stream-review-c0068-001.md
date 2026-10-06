# Review 001: c0068 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0068` (6 files, all inside c0068's Touched modules, its document and its acceptance spec); c0068.md, check.sh, acceptance/stop.spec.luau; R0025.md; c0067 machinery (`moveOnOrigin`, `sweepStale`, `ready`); tracker and testing skills. Ran `scripts/tracker.sh check c0068` (7/7) and `bash tracker/issues/active/c0067/check.sh` (13/13, includes the 13 banned phrases and the no-clipboard grep). The single-line `stop.spec.luau:312` edit (`-q` dropped) is authorized and recorded in the Verification log; not a finding.

Attacked and held: every refusal in `stop` (not a raft, main-checkout guards, first pull, member not in `active/`, wrong status) runs before `moveOnOrigin`/`setStatus`, so nothing is published first; a member in `done/` or backlog refuses naming it. The move back uses the same `moveOnOrigin` and `paths.rewrite` (stamp `prepared`, one commit). The legacy give-back goes through `setStatus` with no move. The first `pullMain` sweeps exactly as `ready` does (only item directories with nothing tracked at HEAD lose their ignored files; untracked non-ignored files are kept and named), so no tracked or untracked user work is deleted; the main checkout is clean at entry, and `prompt.md` is ignored. `gh` runs only when `onGitHub()`; a failed `gh` falls back to "its pull request, if any". The `status` refusal sits inside the build against origin, for every target and every `<to>`, and fires only for `stateOfPath == "active"` (a legacy-started raft in the backlog is unaffected). `mainCheckoutGuards` and `pullMain` are verbatim extractions from `ready`, so the messages (`ready runs in the main checkout`, `ready needs an origin remote`, `ready: cannot fast-forward ...`) are unchanged; `setStatus` is a pure extraction of `status`'s publish body plus the refusal.

### F1 [low] Tracker skill "A failed start" still tells a readied raft's owner to give the claim back with `status <R-id> prepared`
Where: `.claude/skills/tracker/SKILL.md`, Sync and claim, "A failed start" (and "Published or carried", "Whose claim", which still list `status <R-id> prepared` from `active` as an open give-back).
Evidence: after c0067 `ready` claims by moving the raft to `active/` on origin; c0068's new refusal makes `status <R-id> prepared` fail there ("<R> is readied (in active/): use tracker.sh stop <R>"). The paragraph still says "or give your own claim back with `status <R-id> prepared`". Only a legacy-started raft (backlog, `active`) can still use that path.
Critique: a reader following the failed-start advice after `ready` + a failed `start` hits the refusal. The author will be tempted to leave it, since the new bullet "Giving back a readied raft" is nearby.
Consequences: none beyond wording; `stop` is the only way back and is already specified.
Recommendation: in "A failed start" say `tracker.sh stop <R-id>` (readied) or `status <R-id> prepared` (legacy claim); in "Whose claim" say the `status <R-id> prepared` open give-back applies to a legacy claim. No spec change (the c0068 AC7 greps do not pin these sentences).

### F2 [low] Tracker skill says `stop` writes `prompt.md`
Where: `.claude/skills/tracker/SKILL.md`, Worktrees item 1 (the `ready` and `stop` bullet).
Evidence: "`scripts/tracker.sh ready` and `stop`, which publish to `origin/main`, run `git pull --ff-only` there and write the ignored `tracker/rafts/active/<R-id>/prompt.md`". `stop` deletes `prompt.md`.
Critique: wrong behaviour statement in the rule list. Fix is a few words; c0067's AC10 only greps for `prompt.md` in the skill, so it stays green.
Consequences: none.
Recommendation: "... run `git pull --ff-only` there; `ready` writes and `stop` removes the ignored `.../prompt.md`".

### F3 [low] `stop`'s move to the backlog has no origin-side status check
Where: `scripts/tracker/main.luau`, `cmd.stop`, the `moveOnOrigin(all, "backlog", ...)` call (verify argument `nil`).
Evidence: the member check (`m.state ~= "active"`) reads the tree after the pull; `moveOnOrigin` then re-fetches inside `publishFresh`. If a member moved to `done/` between the pull and the publish (another terminal running `tracker.sh done` and landing), `docPath` finds it in `done/` and the commit moves it back to the backlog. This is a race of seconds, and `ready` has the same shape, so it is not high.
Critique: the "a member in done/ refuses" guarantee holds only for the local read. The tempting fix is to re-pull and re-check, which does not close the window.
Consequences: a `verify` callback is the existing hook (`ready` can use it too, outside this issue), so it adds no new state.
Recommendation: pass `verify = function(id, st) return if st == "active" then nil else \`{id} is {st} on origin/main, not active\` end`; no new spec case needed beyond the existing done/ one (the message differs only in the race).

### F4 [low] The GitHub branch of the PR report is unexercised
Where: `cmd.stop`, the `onGitHub()` block.
Evidence: fixtures have no github.com origin, so the `gh pr list --head <b> --state open --json url -q '.[0].url'` path and the "url empty" fallback never run (the design records this as "reviewer checks the code"). Read: the command and flags match the Design; an empty result or a non-zero exit yields "its pull request, if any"; only the first open PR is named.
Critique: if `gh` printed a literal `null` for an empty list the line would read "its pull request null". I believe gh's `-q` prints nothing for null, so this is a hedge, not a failure.
Consequences: a guard (`url ~= "null"`) costs one clause.
Recommendation: add `and url ~= "null"` to the condition; no spec change (not testable in fixtures).

Verdict: approve
