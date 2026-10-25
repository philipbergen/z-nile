# Review 001: c0121 (design mode)
Inputs: origin/prep-c0121 7f3763c8 (c0121.md, check.sh, acceptance/*); prototype proto-c0121 916300f1 on the c0118-done simulation 68f4c5e1, cloned to scratch; its sequestered files are identical to the prep branch's. `check.sh` on the prototype clone: 6/6. Mutants run in the clone: M1 (gh run inline), M2 (engineHash constant), M3 (keyOf constant), all survived. `./zn capture c0121`, `./zn lessons --when design --full` and `--skill review` read.

Attack on the core (F3) found no hole. Tried: a rebinding Host (`evil.example`, `evil.example:<port>`, `localhost.evil.example`, a trailing-dot `localhost.`), an Origin from another loopback port, `Origin: null`, OPTIONS, a GET or form-typed POST to `/api/action`, an `/api/state` read without the header (a cross-site page can't set the header without a preflight, and OPTIONS is a 403), and a top-level navigation to `/` without the token. Every one is refused before any route runs. The bare `localhost` and `127.0.0.1` Host forms (G6) can't come from a rebinding page, because the port is always 1024 or above. The server binds 127.0.0.1 only (E6). The token comes from `/dev/urandom`, isn't in any argv (the CLI never runs `open` on the URL), and appears only in the served page, the guarded `/api/state` and the printed URL. With no referrer policy set, browsers default to `strict-origin-when-cross-origin`, so a PR link sends only the origin. The runner is `process.exec("<top>/zn", args)` and `zn` forwards `"$@"`, so no shell is involved, and ids are checked against `model.home`. A double Retry is refused by c0117's run lock. XSS through documents is closed by c0118's `esc` html renderer. Anything left needs an agent running as the user: a documented limit.

Scope (item 11): the capture's three outcomes are unchanged. F3, F4, F8, F9 and F11 are each designed and specced, apart from the two parts named in F1 and F2. The added Non-goals restate captured limits.

### F1 [medium] "gh never on the request path" (F8) has no case that fails when gh runs inline
Where: c0121.md §5 "never awaited by the request"; server.spec "state fills PR and checks from gh…"
Evidence: mutant M1 turns `task.spawn(function() … end)` in `refreshGh` into a direct call. server.spec still passes 14/14. The `gh` stub returns at once without yielding. Lune's `task.spawn` also runs its function up to the first yield, so with that stub the real code and the mutant behave the same, and no case asserts the first answer's `live.checks == "loading"`.
Critique: F8's main requirement (a 0.5 s, authenticated `gh` call kept off every request) can be met by an implementation that blocks every poll on `gh`. The tempting fix is to assert "loading" on the first call. With an instant stub, that assertion would fail for the correct implementation too.
Consequences: the stub must yield, as the real `process.exec` does, so the spec takes a short real wait. The busy flag then matters: a second request while gh is in flight must not start a second gh.
Recommendation: make the stub yield (`task.wait(0.3)` before it returns) in one case. Assert that the first `/api/state` answers in under 0.2 s with `live.checks == "loading"`, that a second request during the wait leaves `ghCalls` at 1 (the busy flag), and that after the wait the state reads "ok". Add a Rules row "gh is never awaited by a request" with mutant M1.
Lesson: ticket-prep/spec-design-correspondence

### F2 [medium] The real `serve.keyOf` and `serve.engineHash` are never run, so F11's "fixture HEAD change" and F8's rebuild key are fakeable
Where: §5 Rebuilding, §7; server.spec injects `keyOf` and `engineHash` stubs; Rules rows N19–N22
Evidence: mutant M2 (`serve.engineHash` returns a constant) and mutant M3 (`serve.keyOf` returns `"k"`) each pass guard, server and cli: 35 passed, 0 failed. The capture carries F11 as "One case with a fixture HEAD change", but the spec flips a string (`hash = "engine-2"`). F8's "Rebuild the model only when HEAD, origin/main or a worktree's HEAD changed" is tested only through a stubbed key, so a real key that ignores worktree HEADs, or a hash of `HEAD` instead of `HEAD:z-nile/engine`, ships green.
Critique: N19–N22 prove that `model()` reacts to a key and a hash, not that the key and hash track the repository. The tempting fix is to call the real functions once and check that they return a string. That passes for a constant too.
Consequences: a fixture git repo under `.cache` (as cli.spec already builds through `fixture`) with an `origin/main` ref and a linked worktree. `engineHash` must also not change on a commit outside `z-nile/engine`, or every sync would flag the server stale.
Recommendation: add `server.spec` (or `guard.spec`) cases on a `.cache` fixture repo, all through `fixture.git`. (a) `serve.keyOf(root)` changes after a commit on main, after moving `refs/remotes/origin/main`, after a commit in a linked worktree, and after touching `.cache/dispatch/<id>/state.json`, and stays the same when nothing changed. (b) `serve.engineHash(root)` changes after a commit under `z-nile/engine` and stays the same after a commit elsewhere. (c) One `serve.start` case with the default `engineHash` (no stub) on that fixture reads `stale == true` after an engine commit, which is F11's case word for word. Add Rules rows for M2 and M3.
Lesson: testing/pin-call-site-arguments

### F3 [medium] `parsePrs` keeps the oldest PR when a branch has several
Where: serve.luau `parsePrs` (`byBranch[p.headRefName] = …` overwrites); §5
Evidence: `gh pr list` lists newest first (checked on this repo: #120, #119, #118, …). `parsePrs` on `[{number:12, R0020-a, OPEN, FAILURE}, {number:5, R0020-a, CLOSED}]` returns `5 closed none`. The later, older entry wins. This repo already has three head branches with two PRs each (`prep-board-graphs`, `prep-ghost-hunter-jump`, `prep-ready-raft`), and a raft branch gets a second PR whenever the first is closed and the work re-raised. The card then shows the closed PR and "checks none", and Open opens the closed PR. A fork PR whose head branch has the same name also collides.
Critique: this is a wrong result, and the lesson below covers it. The tempting fix is "first wins". That holds only while gh's default order holds.
Consequences: a rule is needed for which PR wins: open or draft over merged or closed, then the highest number. Fork heads (`headRepositoryOwner` ≠ the repository owner) need a decision too.
Recommendation: in `parsePrs`, prefer an open or draft PR, then the highest `number`, whatever the input order. Add `headRepository`/`isCrossRepository` to the `--json` fields and skip cross-repository PRs. Add a guard.spec case with two PRs on one branch in both orders, plus a cross-repository one, and a Rules row.
Lesson: ticket-prep (the "a format must hold every repeat of what it records … never silently keep one" lesson, check at line 215 of the design lessons)

### F4 [low] The usage line for `board --serve` cuts `board`'s continuation line off from it
Where: main.luau usage text
Evidence: `./zn` prints `board --serve [--port N]  serve that page live … (main checkout; stop, retry, open)` followed by `and open it in the browser; -O only writes it`, which belongs to `board [--out PATH] [-O]`.
Recommendation: put the `--serve` line after the continuation, and assert in cli.spec that the line after `board [--out PATH] [-O]` still says "open it in the browser".

### F5 [low] Any failure in `serve.start` is reported as "port N is taken"
Where: main.luau `serveBoard`, `pcall(serveLib.start, …)`
Evidence: a failure in `newToken` (no `od`), in `engineHash`, or any other start error prints "port N is taken (already serving?)".
Recommendation: say "port N is taken" only when the error is the bind failure. Otherwise print "board --serve could not start: <why>".

### F6 [low] Retry answers 202 even when the dispatcher refuses at once
Where: §4 retry; serve.luau `act`
Evidence: a retry on a run whose lock is held (c0117 `lock(dir, true)` refuses) still shows "retry: 202 started …". The refusal goes to a discarded pipe.
Recommendation: wait up to about 1 s for the child. If it has exited by then, answer 200 or 500 with its output, and otherwise 202. Or record the last retry's exit per id and show it in `model.live` on the next poll. Add a case with a runner that fails at once.

### F7 [low] Some cli.spec refusals don't hold a port, so a regression serves and hangs instead of failing
Where: cli.spec "refuses -O, --out and --open…", "refuses a port outside 1024 to 65535" (`80`)
Evidence: a mutant that drops `--open` from the refusal starts a real server in the fixture on 8417 and hangs the spec. Port 80 binds unprivileged on macOS. JC1's "each such case holds the port it passes" is true only because these cases pass no port.
Recommendation: pass `--port <held>` in the `-O`/`--out`/`--open` cases. For the out-of-range ports, check the refusal text before any bind (already done) and add `--port` with a held port where the value allows it.

### F8 [low] JC1's list of processes leaves out `od`, and the CLI wiring is pinned only by OC1
Where: JC1 rubric; Rules row "the CLI wires the real effects … reasoned"
Evidence: guard.spec's token case runs `serve.newToken` (`od`). Nothing pins the `gh` argv or `<top>/zn` beyond the by-hand OC1.
Recommendation: add `od` to JC1's list. Optionally move the three effect closures into an exported `serve.effects(top, exec)` with `exec` injected, and pin the argv in guard.spec.
Lesson: testing/pin-call-site-arguments

## Guesses (for the user, not findings)
- G1 (port 8417), G2 (5 s / 30 s / 60 s), G5 (open: own PR, raft PR, worktree) and G7 (card wording) look sound.
- G3: Ctrl-C and a closed terminal reach the whole foreground group, so a retry dies with the server, as F9 allows. A `kill` of the server's pid alone leaves the child writing to a closed pipe, so it dies at its next write and c0117 marks it lost. That is the same outcome, and worth one sentence in §4.
- G4 departs from the programme review's literal "keep it out of READ_ONLY … update the pin". The exception is equivalent and pinned by cli.spec. The user decides.
- G6 is safe: a rebinding page always sends its own name and a port of 1024 or above.

Verdict: changes
