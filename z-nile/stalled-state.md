# Stalled state

Collected 2026-11-10 10:39 from this worktree. Nothing here was deleted, stopped, or moved.
A row is `keep` when its last commit, or a dirty file, is newer than 2026-11-08 10:39 (48 hours), or a process has its cwd inside it.
A row is `idea` when it is not live and it still names a change worth keeping as a backlog idea: the checkout, branch, or unfinished design can go after you confirm.
A row is `drop` when the change already merged, the pull request was closed, the worktree is detached with no pull request, or the ref is a fixture leftover.

## Totals

| Kind | Rows | keep | idea | drop |
|---|---:|---:|---:|---:|
| Worktrees | 82 | 35 | 38 | 9 |
| Branches with no worktree | 14 | 1 | 11 | 2 |
| Stray refs | 3 | 1 | 0 | 2 |
| Active rafts and issues | 20 | 2 | 18 | 0 |
| Open pull requests | 17 | 9 | 8 | 0 |
| Moot backlog items | 9 | 0 | 2 | 7 |

## Worktrees

| Path | Branch | Last commit | Ahead of origin/main | Uncommitted | Pull request | In use | Recommendation |
|---|---|---|---:|---|---|---|---|
| `/Users/philipbergen/code/pickman` | `main` | 2026-11-09 | 0 | no |  | yes | keep |
| `/Users/philipbergen/code/pickman/.worktree/R0084` | `R0084-board-live-server` | 2026-11-09 | 2 | no | #285 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/bookkeeping-never-blocks` | `bookkeeping-never-blocks` | 2026-11-10 | 4 | no | #291 merged | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/cut-1.3-lighter-process` | `cut-1.3-lighter-process` | 2026-11-10 | 0 | yes |  | yes | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-board-shows-lost-work` | `prep-board-shows-lost-work` | 2026-11-09 | 2 | no | #281 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-design-approval-gate` | `prep-design-approval-gate` | 2026-11-09 | 1 | no | #290 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-dispatch-retry-passes-answer` | `prep-dispatch-retry-passes-answer` | 2026-11-09 | 0 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-provenance-lifecycle-rows` | `prep-provenance-lifecycle-rows` | 2026-11-09 | 1 | no | #289 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-provenance-who-from-git` | `prep-provenance-who-from-git` | 2026-11-09 | 1 | no | #286 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-take-over-lost-claim` | `prep-take-over-lost-claim` | 2026-11-09 | 3 | no | #280 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-ticket-provenance` | `prep-ticket-provenance` | 2026-11-09 | 31 | no | #266 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/prep-work-heartbeat` | `prep-work-heartbeat` | 2026-11-09 | 53 | no | #255 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0260-capture-interview` | `proto-c0260-capture-interview` | 2026-11-07 | 0 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0261` | `proto-c0261` | 2026-11-07 | 0 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0263-raft` | `proto-c0263-raft` | 2026-11-09 | 23 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0265-env` | `proto-c0265-env` | 2026-11-08 | 15 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0265-mut` | `proto-c0265-mut` | 2026-11-08 | 13 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0265-raft` | `proto-c0265-raft` | 2026-11-08 | 14 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0274` | `proto-c0274` | 2026-11-09 | 25 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0274-mut` | `(detached)` | 2026-11-09 | 25 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0274-mut1` | `(detached)` | 2026-11-09 | 25 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0274-mut2` | `(detached)` | 2026-11-09 | 25 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0276` | `proto-c0276` | 2026-11-09 | 24 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0276-env` | `proto-c0276-env` | 2026-11-09 | 23 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0280` | `proto-c0280` | 2026-11-09 | 27 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0282` | `proto-c0282` | 2026-11-09 | 31 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0282-dev` | `proto-c0282-dev` | 2026-11-09 | 31 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0282-mut` | `(detached)` | 2026-11-09 | 31 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0282-mut2` | `(detached)` | 2026-11-09 | 31 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0283` | `proto-c0283` | 2026-11-09 | 35 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0283-mut` | `proto-c0283-mut` | 2026-11-09 | 34 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0283-mut2` | `proto-c0283-mut2` | 2026-11-09 | 34 | no |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/proto2-c0121` | `proto2-c0121` | 2026-11-09 | 8 | yes |  | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/raft-models-readme-capture` | `raft-models-readme-capture` | 2026-11-09 | 11 | no | #287 open | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/zn-fast-gate` | `zn-fast-gate` | 2026-11-09 | 0 | no | #288 merged | no | keep |
| `/Users/philipbergen/code/pickman/.worktree/R0061` | `R0061-z-nile-header-slug-scans` | 2026-10-31 | 14 | no | #172 open | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/R0071` | `R0071-no-leaked-processes` | 2026-11-02 | 13 | no | #215 open | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/capture-local-ci-only` | `capture-local-ci-only` | 2026-10-27 | 1 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/capture-sweeper-kill-c0132` | `capture-sweeper-kill-c0132` | 2026-10-26 | 8 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-c0117` | `prep-c0117` | 2026-10-25 | 147 | no | #117 merged | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/prep-colorful-cli-output` | `prep-colorful-cli-output` | 2026-10-26 | 2 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-conflict-marker-gate` | `prep-conflict-marker-gate` | 2026-10-26 | 1 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-fixture-volume-no-fseventsd` | `prep-fixture-volume-no-fseventsd` | 2026-11-01 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-frame-roundtrip-tolerance` | `prep-frame-roundtrip-tolerance` | 2026-10-26 | 9 | no | #151 merged | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/prep-full-force-final-review` | `prep-full-force-final-review` | 2026-11-08 | 10 | no | #260 open | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-gate-contention` | `prep-gate-contention` | 2026-10-26 | 1 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-guard-follow-ups` | `prep-guard-follow-ups` | 2026-10-05 | 9 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-merge-past-tracker-only` | `prep-merge-past-tracker-only` | 2026-10-31 | 14 | no | #165 open | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-pinned-lune-or-refuse` | `prep-pinned-lune-or-refuse` | 2026-10-26 | 1 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-player-faster` | `prep-player-faster` | 2026-10-26 | 7 | no | #133 merged | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/prep-readme-states-znile-intent` | `prep-readme-states-znile-intent` | 2026-11-08 | 12 | no | #256 closed | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/prep-relevant-review-lessons` | `prep-relevant-review-lessons` | 2026-10-28 | 2 | no | #177 open | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-sweep-counts-other-runs` | `prep-sweep-counts-other-runs` | 2026-11-01 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-sweeper-killed-under-load` | `prep-sweeper-killed-under-load` | 2026-10-31 | 18 | no | #175 open | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-sweeper-killer-next-report` | `prep-sweeper-killer-next-report` | 2026-11-01 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/prep-white-ghost-green-walls` | `prep-white-ghost-green-walls` | 2026-10-26 | 8 | no | #139 merged | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0117` | `proto-c0117` | 2026-10-23 | 12 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0153` | `proto-c0153` | 2026-10-26 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0162` | `proto-c0162` | 2026-10-31 | 8 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-c0172` | `proto-c0172` | 2026-10-27 | 5 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-d0149` | `proto-d0149` | 2026-10-31 | 19 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0109` | `proto-f0109` | 2026-10-25 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0125` | `proto-f0125` | 2026-10-25 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0143` | `proto-f0143` | 2026-10-25 | 2 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0143-deps` | `proto-f0143-deps` | 2026-10-26 | 13 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0143-deps2` | `proto-f0143-deps2` | 2026-10-26 | 7 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0143b` | `proto-f0143b` | 2026-10-26 | 10 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0145` | `proto-f0145` | 2026-10-31 | 14 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0146` | `proto-f0146` | 2026-10-26 | 8 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0147` | `proto-f0147` | 2026-11-01 | 19 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-f0148` | `proto-f0148` | 2026-11-01 | 19 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-linux-jail` | `proto-linux-jail` | 2026-10-18 | 2 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-r0260` | `proto-r0260` | 2026-10-04 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-risky-wall-picks` | `proto-risky-wall-picks` | 2026-10-25 | 0 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-sweeper-report` | `proto-sweeper-report` | 2026-10-26 | 7 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/proto-wall-picks-touch` | `proto-wall-picks-base3` | 2026-10-25 | 8 | yes |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/raft-check-guards-regroup` | `raft-check-guards-regroup` | 2026-10-31 | 5 | no | #167 open | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/raft-frame-roundtrip` | `raft-frame-roundtrip` | 2026-10-26 | 2 | no | #156 merged | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/raft-player-faster` | `raft-player-faster` | 2026-10-26 | 2 | no | #134 merged | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/raft-white-ghost` | `raft-white-ghost` | 2026-10-26 | 2 | no | #142 merged | no | drop |
| `/Users/philipbergen/code/pickman/.worktree/scratch-f0143-picks` | `proto-f0143-picks` | 2026-10-26 | 1 | no |  | no | idea |
| `/Users/philipbergen/code/pickman/.worktree/scratch-f0145-d0124` | `(detached)` | 2026-10-26 | 2 | yes |  | no | drop |

## Branches with no worktree

Local and remote branches other than `main`, including `proto-*`, that no worktree has checked out. Uncommitted is empty because there is no checkout. A remote whose local branch is checked out is listed with that worktree, not here.

| Ref | Last commit | Ahead of origin/main | Pull request | Recommendation |
|---|---|---:|---|---|
| `refs/heads/capture-closure-skips-review` | 2026-10-26 | 4 |  | idea |
| `refs/heads/proto-c0282-next` | 2026-11-09 | 29 |  | keep |
| `refs/remotes/origin/capture-kimi-cli-support` | 2026-10-27 | 2 | #176 closed | drop |
| `refs/remotes/origin/capture-touch-controls` | 2026-10-25 | 3 | #127 closed | drop |
| `refs/remotes/origin/capture-workers` | 2026-11-07 | 1 |  | idea |
| `refs/remotes/origin/omarchy-board-app` | 2026-11-05 | 4 | #243 open | idea |
| `refs/remotes/origin/prep-paid-play-and-continues` | 2026-11-01 | 13 |  | idea |
| `refs/remotes/origin/proto-c0144` | 2026-10-26 | 6 |  | idea |
| `refs/remotes/origin/proto-c0163` | 2026-10-26 | 3 |  | idea |
| `refs/remotes/origin/proto-check-paths-home` | 2026-10-26 | 4 |  | idea |
| `refs/remotes/origin/proto-f0110` | 2026-10-25 | 6 |  | idea |
| `refs/remotes/origin/proto-merge-past-tracker-only` | 2026-10-31 | 11 |  | idea |
| `refs/remotes/origin/proto-scripts-refuse-conflicts` | 2026-10-26 | 6 |  | idea |
| `refs/remotes/origin/proto2-c0118` | 2026-11-07 | 5 |  | idea |

Stray refs outside `refs/heads` and `refs/remotes`:

| Ref | Date | Recommendation |
|---|---|---|
| `refs/fakemain` | 2026-11-07 | drop |
| `refs/fm2` | 2026-11-07 | drop |
| `refs/tags/archive/fixture-leak-2026-09-30` | 2026-09-30 | keep |

`refs/tags/archive/fixture-leak-2026-09-30` is a tag someone named archive. The other two are fixture refs (`refs/fakemain`, `refs/fm2`) from 2026-11-07.

## Active rafts and issues

Every raft and issue document directly under a project's `.tracker/**/active/`. The claim is the `status:` stamp. `idea` means the feature stays on the tracker and the `active/` placement is the part to undo, after you confirm.

| Id | Title | Claim | Last change | Branch | Pull request | Recommendation |
|---|---|---|---|---|---|---|
| R0061 | c0131 header, used slugs refused, finished scans | `active-pink-indigo-copper` | 2026-10-26 | R0061-z-nile-header-slug-scans | #172 open | idea |
| R0068 | Review lessons to the step | `active-badger-quiet-violet` | 2026-11-01 |  |  | idea |
| R0070 | Temp trees fixture identity | `active-falcon-mongoose-mongoose` | 2026-11-01 |  |  | idea |
| R0073 | Shared fixture images | `active-jolly-silver-walrus` | 2026-11-01 |  |  | idea |
| R0078 | C0075 c0083 spec fixes | `active-plucky-lucky-copper` | 2026-11-01 |  |  | idea |
| R0080 | Closure design record | `active-falcon-quiet-jolly` | 2026-11-02 |  |  | idea |
| R0084 | Board live server | `active-violet-marble-indigo` | 2026-11-09 | R0084-board-live-server | #285 open | keep |
| c0121 | Board server with live actions | `active-violet-marble-indigo` | 2026-11-09 | proto2-c0121 |  | keep |
| c0122 | Ref guard accepts a fetch with nothing new | `active-badger-quiet-violet` | 2026-11-01 |  |  | idea |
| c0134 | C0131 accept spec header | `active-pink-indigo-copper` | 2026-10-26 |  |  | idea |
| c0135 | New issue refuses a used slug | `active-pink-indigo-copper` | 2026-10-26 |  |  | idea |
| c0136 | Review lessons go to the step that erred | `active-badger-quiet-violet` | 2026-11-01 |  |  | idea |
| c0137 | Finished .claude scans pass vacuously from z-nile/ | `active-pink-indigo-copper` | 2026-10-26 |  |  | idea |
| c0138 | Trail compaction reset | `active-badger-quiet-violet` | 2026-11-01 |  |  | idea |
| c0156 | Whole file pins keep newlines | `active-badger-quiet-violet` | 2026-11-01 |  |  | idea |
| c0161 | Closure skips design review | `active-falcon-quiet-jolly` | 2026-11-02 |  |  | idea |
| c0173 | C0075 reads the local jail wiring | `active-plucky-lucky-copper` | 2026-11-01 |  |  | idea |
| c0174 | C0083 read deploy workflow | `active-plucky-lucky-copper` | 2026-11-01 |  |  | idea |
| c0178 | Shared fixture images | `active-jolly-silver-walrus` | 2026-11-01 |  |  | idea |
| c0194 | Temp trees under repo | `active-falcon-mongoose-mongoose` | 2026-11-01 |  |  | idea |

## Open pull requests

| Number | Title | Age (days) | Gate | Recommendation |
|---:|---|---:|---|---|
| 290 | tracker: prep c0283 Design approval gate | 0 | success | keep |
| 289 | tracker: prep c0282 Provenance lifecycle rows (WIP, round 1 answered pending; held draft) | 0 | success | keep |
| 287 | tracker: raft R0090 R0092 (c0261, c0264 split; c0260 unfolded) | 0 | success | keep |
| 286 | tracker: prep c0280 Provenance who from git (WIP, draft) | 0 | success | keep |
| 285 | R0084: Board live server | 0 | success | keep |
| 281 | tracker: prep c0276 Board shows lost work (prepared; held draft) | 0 | none | keep |
| 280 | tracker: prep c0274 Take over lost claim (WIP, review round 4 open) | 1 | success | keep |
| 266 | tracker: prep c0263 Ticket provenance (the record, layer 1) | 1 | success | keep |
| 260 | WIP: c0262 Full force final review (held until c0248 and c0260 are prepared) | 2 | none | idea |
| 255 | tracker: prep c0265 Work heartbeat and lost items (core layer, design ready, prepared; held draft) | 2 | none | keep |
| 243 | c0257: Omarchy board app | 4 | success | idea |
| 215 | R0071: No leaked processes | 8 | success | idea |
| 177 | tracker: prep c0166 Reviewers read only relevant lessons | 12 | failure | idea |
| 175 | tracker: prep c0132 Sweeper killed under load | 14 | failure | idea |
| 172 | R0061: c0131 header, used slugs refused, finished scans | 14 | success | idea |
| 167 | tracker: raft R0062 regrouped (c0141's record refreshed) | 14 | failure | idea |
| 165 | tracker: prep c0152 Merge past tracker only main | 14 | failure | idea |

## Backlog this plan makes moot

The publish sweep, the board rebuild on every push, and a spend row's own push have no backlog issue. Step 1.2 removed them from the engine. The sweeper issues (c0132, c0167, c0168, c0225) are the process reaper, not that sweep, so they are not in this table.

| Id | Title | Why it is moot | Recommendation |
|---|---|---|---|
| c0083 | Split harness and game specs into two suites | Step 1.1 already runs a game change without z-nile's specs and a z-nile change without the game's. This prepared design is the same split. | drop |
| R0030 | Suite split | The raft for c0083. The split it prepares already landed. | drop |
| c0152 | Merge past tracker only main | Step 1.2 re-runs a gate only when the merged commits touch the pull request's inputs. A tracker-only move of main no longer forces a full re-run. | drop |
| c0180 | Affected selection by command, end to end final | Phase 2 replaces the require-graph selector with a watch file. The selecting-tests idea stays; this graph design does not. | idea |
| c0233 | Selector finds digest pinning specs | It patches the require-graph selector and the results digest. Phase 2 deletes both. | drop |
| c0240 | A merge failure teaches the selector | The repair idea stays, on the watch file (a missed test adds the files it needed). This issue's selector design does not. | idea |
| c0241 | c0180 re-prep after the c0165 split | A re-prep of the require-graph selector, which Phase 2 drops. | drop |
| c0255 | Reuse digest marks untracked paths | Phase 2 deletes the results database and its digest. The hole closes because the digest goes away. | drop |
| c0281 | Board round rule spy pin | The multi-round rule it pins is gone. One round, then the human. Old review files still parse without this pin. | drop |

Moot backlog rows: 9. keep 0, idea 2, drop 7.

