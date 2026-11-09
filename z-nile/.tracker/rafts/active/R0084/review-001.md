# Review 001: R0084 (code mode)
Inputs: HEAD 5b086f47 (branch R0084-board-live-server, PR #272) against origin/main 1758cf21 (merge base ed65953c); `git diff origin/main...HEAD`; R0084.md; c0121.md, its check.sh and acceptance/ (sequestered); prototype `proto2-c0121` fa44f524 over base 3993dca2.

Checked and clean:
- **The carry equals the reviewed prototype.** `diff <(git diff 3993dca2 fa44f524 -- <the 8 paths> | grep -v '^index ') <(git diff origin/main...HEAD -- <the 8 paths> | grep -v '^index ')` prints nothing. Each of the 8 files is also byte-identical to fa44f524's (`git diff --quiet fa44f524 HEAD -- <path>` for each one). Main has changed no code since the base: `git diff --stat HEAD...origin/main -- z-nile/engine z-nile/tests z-nile/lib z-nile/README.md z-nile/skills zn` is empty.
- **Sequestration.** The `--find-renames=100% --name-status` listing over `check.sh` and `acceptance/**` is empty, and `git diff --summary` shows only the two new files (R0084/spend.md, engine/serve.luau), with no mode change.
- **`./zn check c0121`: 7/7** (AC7 read origin from https://github.com/philipbergen/pickman.git).
- **Regression specs, run by hand**, 43 passed, 0 failed:
  - c0077 cache-paths, `tooling/repo-fence`, `tooling/dispatch-texts`: 17 passed;
  - c0048 board-docs and board-workflow, c0057 guard and open, c0073 board-stats: 26 passed.
  - AC6 also ran c0118's seven specs, c0115 readme, c0042, c0107, `tooling/board` and `tooling/tracker-guarded`.
- **Guards** (serve.luau:59-109). I read every row of §3 against the code:
  - Host is matched exactly, so `localhost.evil`, `evil:port` and a missing Host are all refused;
  - OPTIONS gets 403 before any other check, with no `Access-Control-*` header anywhere in the module;
  - an Origin present and not one of the two loopback origins is refused, `null` included;
  - the page needs `?token=` and GET;
  - `/api/*` needs `X-Zn-Token`;
  - an action must be a POST whose Content-Type starts with `application/json`;
  - every other path gets 404.
- **Ids and execution.**
  - Ids are checked as strings against `m.home` (:131), and actions are argument arrays only: `exec("<top>/zn", args, {cwd})`, `open`/`xdg-open { target }`, `gh GH_ARGS`. No `sh -c` anywhere in serve.luau.
  - The bind is `address = "http://127.0.0.1"` (:458).
  - gh runs in a `task.spawn` behind a busy flag and a TTL. It is never awaited (:357-373).
- **G3.** The retry is `process.exec` with no new session, and c0117's supervisor stays in the caller's group (runner.luau:47-49 setpgrp's only the CLI). Its INT handler and its lifeline kill the step's group, so Ctrl-C on the server reaches the step.
- **The rest of §4, §7 and §8.**
  - The stale flag compares `git rev-parse HEAD:z-nile/engine` with its value at start.
  - `board` stays in READ_ONLY, and `--serve` is excepted at main.luau:6040.
  - The main-checkout refusal, the port bounds and the start error all match §8.
- **The static page.** `actions()` and the poll are gated on `model.live`. `prText` keeps the static "live on the served board" text.

### F1 [high] Retry on a card that never ran starts the item's whole headless chain, so the board can start a model run on any id it shows
Where: z-nile/engine/serve.luau:150-151 (`retry` plans `./zn dispatch retry <id>` for any id in `m.home`, with no run-state check); z-nile/engine/dispatcher.luau:2014-2055 and :96-101; c0121.md Non-goals ("Starting a model, or any action besides stop, retry and open").

Evidence:
- `serve.plan(m, "retry", id)` returns `{ "dispatch", "retry", id }` for every id the model has: every new ticket, every prepared raft, every done item. Stop gets the 409 guard (:138-141) because "`./zn dispatch stop` on an id with no run would create a state folder for it". Retry has no such guard.
- c0117's `retry` branch does this on an id with no state:
  - `lock(dir, true)` runs `fs.writeDir(dir)` (:267-268), so the folder is made;
  - `load(ctx, id)` returns `blank(id, dir)`, whose `mode` is `"chain"` (:100-101);
  - `guardStart` and `flush` run, then, since `mode ~= "step"`, `dispatcher.chain(ctx, id, opts, st)` (:2052-2053).
- That is the full pipeline from the item's tracker state, up to `dispatch.MAX_ACTIONS = 30` actions: design, raft, ready and run, each a model step that spends tokens, pushes branches and opens PRs. It is the same as `./zn dispatch <id>`.
- So one click on Retry on a backlog ticket's card starts an unattended design-to-PR run. AC2 pins this behaviour: server.spec:287-291 retries R0030, which has no dispatch state in the fixture's facts (:105-121), and expects the runner to run.
- Not run: running it would start real model steps. The path above is read from the code, and each hop is quoted.

Critique: the captured outcome is "The only actions are stop, retry and open", and the Non-goals exclude starting a model. On a card with no run, "retry" means start, which goes beyond what the user captured. Stop's own 409 shows the author saw that a stateless id is not a run. The fix the author will be tempted to make is to refuse retry with no state in `serve.plan` (409, like stop). That turns AC2's "a retry the dispatcher refuses at once…" case red: it sends retry on the stateless R0030 and expects the runner's refusal. Hiding Retry on stateless cards in the page instead turns AC3 red: page.spec's f0021 has `dispatch = {}` and expects Retry on it. Every fix in code needs a sequestered spec to change.

Consequences:
- A 409 for retry with no state brings a new rule: what "a run" is for retry. Is it any state.json, or only a non-terminal or retryable outcome (`failed`, `lost`, `stopped`, `tripwire`, `missing`)? What about `ok` with `follows`, where the chain already moved on (guard.spec:209 retries such an f0021)?
- The page then needs to say why Retry is refused, or not show it. The docs (zz-rules board row, which AC5 pins word for word) would gain a sentence.

Recommendation: escalate to the user (zz-execute stop conditions): the specs that pin it are sequestered. The options:
- (a) Retry refuses an id with no run state (409 "nothing to retry for <id>", like stop), and the page shows that answer. This needs a re-prep that edits server.spec's R0030 case (give R0030 a `failed` state, keep the held-lock refusal) and adds a guard.spec case for 409 on a stateless id. Cost: one prep round on the specs.
- (b) The user decides that Retry on a never-run card starts its chain. Record `Decided with the user` in c0121, and have the zz-rules board row say "retry on a card with no run starts its chain (`./zn dispatch <id>`)". That needs a sequestered docs edit too, or a README-only note.
- (c) As (a), but only for outcomes in an explicit retryable set. Same cost as (a), and the user names the set.

### F2 [medium] The server runs under `./zn`'s 1800 s CPU limit, and each poll costs about 0.24 s of CPU, so one open tab gets the server killed by SIGXCPU within about 9 hours
Where: zn:24-29 (`zn_lower_cpu "$lim"` with `ZN_ENGINE_CPU` default 1800, then `exec lune run z-nile/engine/main`; `ulimit -t` sets both the soft and the hard limit, so the engine can't raise it); z-nile/engine/serve.luau:448-451 (every `/api/state` runs `statsOf(m)` and `board.encode` of the whole model); c0121.md Scalability ("about 2.7 MB today").

Evidence: a probe (`./zn run --time 200 -- /usr/bin/time -p lune run …/scratchpad/probe/cpu2.luau N`) builds the real main checkout's model with `worktreeSpend = true` and encodes `{ model, statsHtml = board.statsHtml(m) }` N times.

| run | real | user | sys |
|---|---|---|---|
| N = 0 | 1.25 s | 0.28 s | 0.26 s |
| N = 20 | 5.84 s | 4.98 s | 0.28 s |

- That is about 0.235 s of the server's own CPU per poll, and the body is 6,714,630 bytes (from a first probe), not 2.7 MB.
- At one poll per 5 s that is 720 × 0.235 ≈ 170 s an hour, plus about 60 rebuilds an hour at 0.4 to 0.8 s each. That comes to about 190 to 220 s an hour, so the 1800 s limit is reached in 8 to 9.5 hours with one foreground tab, and in 4 to 5 hours with two.
- Then the kernel kills the server with SIGXCPU. The page says "the server did not answer", and a retry the server started is left to die at its next output line (§4's pid-kill case).
- c0191 (landed before the prototype's base: `git merge-base --is-ancestor 71a5d1c4 3993dca2`) set this limit for engine loops. Neither c0121's design nor its Scalability section accounts for it.

Critique: the server exists to be left open beside running rafts, so a long session is its normal use. The fix the author will be tempted to make is to raise `ZN_ENGINE_CPU` for `board --serve` inside zn. That weakens c0191's guard for one command, edits a file outside the Touched modules (zn), and touches c0191's `engine-cpu.spec`.

Consequences:
- Caching the encoded body makes the per-poll cost near zero, but `live.checksAge` changes every second. The cache must hold the model's JSON without `live`, with the `live` object spliced in per request, or `checksAge` must move out of the model into a field of its own beside `model`.
- The 60 s rebuild (G2, the user's) still costs about 25 to 50 s an hour, so the server still dies, after about 36 to 70 hours. That is a stated bound, not a crash within a working day.

Recommendation: within the design, encode the model and its `statsHtml` once per model build and per gh refresh, not once per poll. Add an unsequestered `z-nile/tests/tooling/serve-*.spec.luau` case (AC7 allows it): two `/api/state` calls in one model window call the injected `statsHtml` once, and their bodies differ only in `live`. Then measure again with the probe above and record it in the Verification log. Escalate to the user whether `board --serve` should run under a larger `ZN_ENGINE_CPU`, with the remaining bound printed at start ("this server stops after about N h of CPU; ZN_ENGINE_CPU raises it"). That is a change to c0191's rule. Also correct Scalability's 2.7 MB to the measured 6.7 MB.

### F3 [low] A `javascript:` link in any item's document runs in the served page's origin, which now holds the action token
Where: z-nile/engine/board.html:154 (the marked config escapes raw HTML but leaves link hrefs alone), :339 and :361 (`marked.parse(issue.body)` into the pane); :311-316 (`act` posts with `model.live.token`).

Evidence: `./zn run --time 20 -- node -e '…marked.parse("[x](javascript:alert(document.cookie))…")'` with the vendored marked v18.0.14 prints `<a href="javascript:alert(document.cookie)">x</a>`. On the static page that is harmless: no token, and a `file://` origin. On the served page, a click on such a link in any tracked document runs script that can read `model.live.token` and POST `retry` or `stop` for any id. Through F1, that includes starting a chain.

Critique: tracked documents reach main by PR, so the attacker needs a merged document and a click. That makes this low, but c0121 is what gives the page's origin the power to act. The tempting fix is a regex over `marked`'s output, which misses entity-encoded schemes (`jav&#x61;script:`).

Consequences: a link renderer that allows only `http:`, `https:`, `mailto:`, `#…` and relative hrefs changes how existing documents render: a link with another scheme becomes text. No current document is known to use one; check with `git grep -nE '\]\((javascript|data|vbscript):' -- '*.md'`.

Recommendation: in board.html, add a marked `link` renderer that resolves the href with `new URL(href, location.href)`, keeps only those schemes, and renders anything else as escaped text. Cover it with a node-harness case in a new `z-nile/tests/tooling/serve-*.spec.luau` (a `javascript:` and an entity-encoded href both render without an `href`).

## Judged criteria (code mode only)
- JC1: pass. I read all five sequestered specs and ran them (`./zn check c0121`, 7/7).
  - Every `runner`, `opener` and `gh` passed to `serve.start` is a Luau closure that records and returns: server.spec:71-95, :433-441 and :483-491. `serve.effects` is driven only with a recording `exec` (guard.spec:315-345).
  - The processes the specs start:
    - `git`, raw `init` on fixture paths and the rest through `fixture.git` on `.cache/c0121-*`;
    - `node`, page.spec:96, whose sandbox has `fetch` and `setInterval` stubs and no network;
    - `od`, through `serve.newToken` in guard.spec;
    - the fixture's own `./zn` and `nogit/zn`, cli.spec:23 and :110;
    - `pwd -P`, cli.spec:18 and server.spec:24, a read with no effect, though not on the rubric's list.
  - No real `gh`, `open`, `xdg-open` or `./zn dispatch` is reachable from any spec.
  - Every server is stopped: the main server in the last case (server.spec:525-529, which also proves a request afterwards fails), and the two extra servers in their own cases (:469, :522). A case that fails before its `stop()` still leaves nothing, because each spec process ends with `process.exit` (tests/run.luau:361, :411).
  - Every cli.spec case that lets `./zn` get as far as binding holds its port first (`occupy()`).
  - Observation for a future capture, not a finding against this branch: the port-range case (cli.spec:68) passes `1023` without holding it. On macOS an unprivileged process may bind ports below 1024 (not run here: the brief forbids binding a real port outside the specs). A regression that dropped only the lower bound would make that case start a real server, which serves until the runner's timeout.

Verdict: changes
