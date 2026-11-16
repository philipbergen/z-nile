# Review 002: c0121 (design mode)
Inputs: origin/prep-c0121 857243aa (c0121.md, check.sh, acceptance/*, design-review-001.md, design-refute-001.md); prototype proto-c0121 458b291d, cloned to scratch. Its c0121.md, check.sh and five acceptance specs are byte-identical to the prep branch's. `./zn check c0121` on the prototype clone: 6/6.
Dropped from review-001: none. Every refutation (F1 to F8) holds, checked on the prototype as below.

Verification of round 1:
- F1: mutant M1 (`gh` called inline instead of in `task.spawn`) is now killed by server :: "never waits for gh…".
- F2: mutant M2 (constant `engineHash`) is killed by two server cases, and mutant M3 (constant `keyOf`) by one.
- F3: `parsePrs` ranks open or draft over the others, then by number, and skips `isCrossRepository`. N38 ("last one wins") and N41 (`isCrossRepository` dropped from `GH_ARGS`) are killed.
- F4: the usage order is fixed; `./zn` prints the continuation line directly under `board [--out PATH] [-O]`.
- F5: `serve.startError` and main.luau:5231 are fixed.
- F6: N40 (no wait for the retry) is killed.
- F7: the -O, --out and --open cases hold the port they pass.
- F8: `od` is in JC1, and `serve.effects` is pinned.

Spot-run mutants that were killed:
- Host prefix match;
- Origin check removed;
- OPTIONS allowed;
- Content-Type check removed.

Security re-try against a live `serve.start` on 127.0.0.1:47321, with stub effects:
- **DNS rebinding.** A Host of `evil.example:<port>`, `localhost.evil.example:<port>` or `localhost.:<port>` gets 403.
- **CSRF.**
  - A text/plain POST with a foreign Origin gets 403.
  - A POST with no Origin and no token gets 403.
  - `Origin: null` gets 403.
  - OPTIONS gets 403, with no CORS headers.
- **The token.**
  - `/` without the token gets 403.
  - A wrong `X-Zn-Token` gets 403.
  - The token in the query of an /api/ call gets 403.
- **A GET that acts.** `GET /api/action` with the token gets 405.
- **Shell injection.**
  - An id of `R0001; touch /tmp/pwn` gets 400 "unknown id".
  - An id given as an array gets 400.
  - An id of `__index` gets 400.
  - Neither the runner nor the opener was called for any of these.
- **Loopback-only binding.** `lsof` shows `127.0.0.1:47321 (LISTEN)`, and the LAN address is refused.

Under "detect, not prevent", anything left needs an agent running as the user.

### F1 [medium] Loopback-only binding is claimed by AC2 and §3, but no case fails when the server binds every interface
Where: serve.luau:425-426 (`address = "http://127.0.0.1"`); c0121.md §3 "The server binds 127.0.0.1 explicitly (E1, E6)"; AC2 "the in-process server on 127.0.0.1"; no Rules row
Evidence: mutant `address = "http://0.0.0.0"` passes guard.spec and server.spec, 35 passed and 0 failed. E6 proved the bind once, by hand and outside the jail. No spec pins it. Every spec reaches the server through 127.0.0.1, which answers under either bind.
Critique: a Checked criterion's text ("on 127.0.0.1") and one of F3's named defences can be dropped without the gate noticing. The 128-bit token means a LAN host still can't act, so this is a fakeable criterion, not a live hole. The tempting fix is to connect to the machine's LAN address and expect a refusal. The jail and CI may have no LAN address or may block it, so that case would be flaky or skipped.
Consequences: an injected listener adds one optional `Options` field. A mutant that ignores the field and calls `net.serve` directly would also skip the stub's recording, so the case must assert that the stub was called.
Recommendation:
- Add `listen: ((port: number, cfg: any) -> any)?` to `Options`, defaulting to `net.serve`. `serve.start` always passes its address through it.
- In one server.spec case, wrap the real `net.serve` in a recording stub. Assert that it was called once, with `cfg.address == "http://127.0.0.1"` and the port passed, and that the server still answers.
- Add a Rules row "the server binds 127.0.0.1 only", with the mutant "binds 0.0.0.0".

### F2 [low] A draft PR isn't preferred to a closed PR with a higher number
Where: serve.luau:185 `rank`; Rules row N38 and the guard case "keeps one PR per branch: open or draft over…"
Evidence: the mutant that ranks only `open` (draft treated as closed) passes guard.spec and server.spec. The case never pairs a draft with a higher-numbered closed PR, so the "or draft" half of the rule is untested. It is rare in practice: the newer PR is usually the higher number.
Recommendation: add to that guard case one draft PR (#5) and one closed PR (#9) on the same branch, in both orders. Expect #5 with state "draft".

### F3 [low] §4 still says retry "answers 202 at once", next to the new 1 s wait
Where: c0121.md:112
Recommendation: change it to "answers 202 once it has run for `serve.RETRY_WAIT`, or with the dispatcher's output if it exits sooner".

Verdict: changes
