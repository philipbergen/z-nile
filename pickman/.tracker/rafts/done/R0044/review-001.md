# Review 001: R0044 (code mode)
Inputs: HEAD 451f62a5 on R0044-hiscores-remember-top-ten; `git diff origin/main...HEAD` (origin/main 9f0cdcbb, merge-base 8fff3d29; 8fff3d29..origin/main changes nothing under `pickman/src` or `pickman/tests`); R0044.md; d0124.md, check.sh, acceptance/*.spec.luau, design-review-006/007; `experiments/prototype.patch`; lessons (`./zn lessons --skill zz-review --full`, `./zn lessons --when build`).

Evidence run:
- `z-nile/check.sh --full` in the worktree: `GATE PASSED (full)`, pickman 1684 passed, 0 failed, 255 spec files (320.1 s).
- `./zn check d0124`: 7/7 criteria passed.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` printed nothing. The move to `active/` is already in the merge-base. `git diff --summary origin/main...HEAD | grep -i mode` shows only `create mode 100644 …/R0044/spend.md`.
- The code is the prototype. `git apply --check -R --directory=pickman experiments/prototype.patch` on HEAD succeeds for all 8 files, so the 61-mutant record from prep applies to this code. `git grep -n -E '^(<<<<<<<|=======$|>>>>>>>)' HEAD -- pickman/src` finds nothing. FlowView keeps f0146's `Logic/Pad` require and `Pad.CONTINUE` binding beside the new Rank handler.
- Order of the best read in Boards (zz-test/yielding-stubs-pin-order). I ran this in a scratch clone outside the repo. Replacing `readBest(player, now)` with `coroutine.wrap(readBest)(player, now)` gives 24/1 on adapters.spec. The failing case is "requests while a player's best is being read …", which expects 4 and gets 5. So in the engine, a first all-time answer sent without its best (GetAsync yields) is caught on an assertion. The `task.spawn` variant fails 10 cases, but only on a load error (`task` is nil in the lobby env), so the coroutine mutant is the one that counts.

Roblox-only behaviour, checked by reading (the stub engine can't show these):
- **UpdateAsync** (`HiscoreStore` `top.update`). The transform doesn't yield or call `io`. It returns nil to cancel, and it keeps `place` and `blind` from its last call only. Roblox passes a second `keyInfo` argument, which the transform ignores harmlessly. A cancelled write returns no error, so `known` follows the last call. That matches d0124 E1.
- **GetAsync caching** (4 s per server). The lobby's list read and best read can be up to 4 s stale on top of CACHE_TTL. That has the same freshness as the per-player board before this raft, so it isn't a regression.
- **Remote nil holes.** `FireClient(player, run, nil, 10)` and the Board answer's `(…, rank=nil, failed, best)` pass nils in the middle of a vararg tuple, which Roblox keeps by position. The Board remote already sent a nil rank in the middle before this raft (f0026). Trailing nils (`best` on day and week) are dropped, and the client reads them as nil.
- **The player-leave race in Boards.** A leave during the GetAsync deletes the marker, so the result is dropped (`bests[userId] ~= mark`). A quick rejoin gets a new marker, and the old read loses to it. Under Deferred signals, an OnServerEvent queued before the disconnect runs before PlayerRemoving, so no marker can be stored after the leave and stay `reading = true` for good.
- **Server authority.** The client sends only a board id. The best is read by the asker's own `UserId`. The place comes from the server's own write, and the Rank remote is server-to-client only.
- **Performance.** Per run there is one more UpdateAsync, sorting at most about 21 entries. Per lobby request there is at most one more GetAsync per player per 15 s. Each packet gains one number, or one small table.

### F1 [low] Two new comment lines run past the 110-column limit set in `stylua.toml`
Where: `pickman/src/server/Ranks.luau:2` (143 columns), `pickman/src/shared/Logic/Hiscores/init.luau:46` (138 columns, the trailing comment on `DriveResult`).
Evidence: `awk 'length > 120 {print FILENAME": "FNR": "length}'` over the five changed server and Logic files printed only these two lines. `git show origin/main:pickman/src/server/Ranks.luau | awk 'length>120'` printed nothing. StyLua doesn't wrap comments, so the gate passes.
Critique: these lines don't match the house style, and the trailing comment on the type alias is hard to read.
Consequences: none.
Recommendation: wrap the Ranks header comment, and move the `rows` note above the `DriveResult` line as its own comment. No spec is needed.

## Judged criteria (code mode only)
None. d0124 lists no Judged criteria; O1 and O2 are Observed (Beta).

Lesson candidates: none.

Verdict: approve
