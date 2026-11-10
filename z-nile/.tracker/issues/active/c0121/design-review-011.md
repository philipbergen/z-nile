# Review 011: c0121 (design mode)
Inputs: prep-board-server2 80125e67 (c0121.md whole, check.sh, acceptance/ specs, overrides.sh, overrides.patch, harvest.md, design-review-010 and design-refute-010, `git diff 73952665 80125e67`); proto2-c0121 7bca94a6 (`git ls-remote origin refs/heads/proto2-c0121` → 7bca94a6…; `git diff fa44f524 7bca94a6`: serve.luau, board.html, zz-rules); origin/main ae926c87 after `git fetch origin main` (since 3993dca2 it changed tracker files, lessons, `z-nile/next`, and the c0074, c0080 and c0269 acceptance specs; no engine file). Scratch clone `.worktree/prep-board-server2/.cache/r011/repo`, made by `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r011/setup.sh`: `main` = origin/main plus the prep's c0121 folder, and `raft` = main plus an empty start commit plus step 1's apply. Probes are in the clone's `z-nile/.cache/probe/` (`cpu.luau`, `race.luau`, `links.js`), and the mutants are in the scratchpad's `r011/mut.sh` and `r011/mut2.sh`. Every probe ran through `./zn run --time …`.
Round 1 of the second re-prep (G9, G10, and code review 001's F3 of R0084).

## What holds (run)
- **Step 1, replayed on today's main**, gives the result the design expects at every point:
  - `merge-base --is-ancestor 7bca94a6 origin/proto2-c0121` succeeds.
  - Every non-new watched path exists on main, and `serve.luau` doesn't.
  - `git log --first-parent 3993dca2..origin/main -- <watched>` prints nothing.
  - The apply of `git diff 3993dca2 7bca94a6 -- <8 paths>` exits 0 with every path clean.
  - `git diff 7bca94a6 HEAD -- <8 paths>` is 0 lines.
  - `overrides.patch` is byte-identical to the prototype's diff of c0118's `docs.spec`, and that diff is unchanged since fa44f524.
- **`./zn check c0121` on the replayed raft: 7/7.** AC7 passes with the changed sequestered `docs.spec`.
- **c0269's new `titles.spec` on the replayed raft: 3/0.** It is the only new promoted spec on main that scans spec text.
- **c0120 `check-paths.spec`** from `z-nile/` in the prep: 4 passed, 0 failed.
- **c0117's contract greps** ran on `origin/main:z-nile/engine/dispatcher.luau`, which is byte-equal to 3993dca2's (`cmp`). The results:
  - grep 1: `73: follows: string?` and `1848: st.follows = action.target`;
  - grep 2: exactly `986: … "running", mode`;
  - grep 3: failed 8, lost 1, missing 1, stopped 1, tripwire 7, with the nil clears at 1790 and 2044.
- **G9's test is the right one.**
  - The board's reader (board.luau:688-708) keeps a state only when `state.json` exists and decodes to a table. The dispatcher's `loadAt` (dispatcher.luau:104-122) returns `blank` for exactly the files the board drops (missing or undecodable). So every id the board shows as stateless is one where `./zn dispatch retry` would start from a blank chain, and the two readers agree.
  - A follow makes the raft's own state (`load(ctx, action.target)`, dispatcher.luau:1849-1853), so a followed raft card has its own state and is retried.
  - A state whose outcome is nil (after the clear at :2044, or a chain that stopped at a gate on its first action, :1814-1818) is a state, and is retried. Retrying it is legitimate: the user started that run.
  - A raft whose members ran but which never followed has no state of its own, and is refused. That is correct: `retry R…` would start the raft's chain.
  - There is no 60 s race on the action path: `act` calls `model()`, which runs `keyOf()` fresh (serve.luau:394). `keyOf` lists every `state.json` with its mtime (:318-329), so a state created or removed since the last build forces a rebuild before `plan`.
  - The Retry button stays, and the page shows any action's `status` and answer (board.html:319-320), so a refused retry reads `retry: 409 refused: nothing to retry for <id>: it has never run`.
  - My X4 mutant (retry allowed only after a non-`ok` outcome) is killed in guard.spec (17/2) and server.spec (21/2).
- **G10's splice is valid and equal.** `board.encode` (board.luau:1245-1274) writes an object for any non-empty keyed table, and the model always has `rafts`, `issues` and `home`, so `string.sub(…, 1, -2)` removes the object's own `}`.
  - `live` is always set by `model()`, so `board.encode(live)` never sees nil. If an encode raised, the pcall would leave `encoded.gen` unset and the next `model()` would set `m.live` again.
  - On the real tree, the old and new bodies decode equal: python `json.load` of both, `a == b` → True.
  - The saving is real. Steady poll on the 6.7 MB model went from 0.102 s to 0.0028 s of CPU (`cpu.luau`, 10 polls each). A rebuild poll costs 0.26 s in both.
- **The mutants in the table hold:**
  - N52, the link function removed: page 8/1, killed on the link case. My first spelling, an unknown renderer key, crashed the page script instead, so it was not used as the N52 result.
  - N53: page 8/1.
  - N54: server 22/1.
  - N55: guard 18/1 and server 22/1.
  - X1 (the generation without `gh` answers): server 21/2, killed by "state fills PR and checks".
  - Base: guard 19/0, server 23/0, page 9/0.
- **Scope**: the diff since 73952665 adds to Problem only the two `Decided with the user (2026-11-08)` lines. Title and Solution are unchanged.

### F1 [high] The link fix doesn't hold: an entity-encoded scheme survives as a live `javascript:` href, and AC3's link case passes it, a blocklist and a renderer that strips nothing
Where: board.html:157-165 (the renderer tests `t.href` raw, then returns `false`, so marked writes the href verbatim); c0121.md:139 (§6 "Document links"); AC3 (c0121.md:334, "a document link keeps only a safe scheme"); page.spec.luau `LINKS` and the case "a document's link keeps only a safe scheme…"; Rules row N52/N53 (c0121.md:326).
Evidence: `links.js` extracts the page's own `marked.use({ renderer: … })` block from board.html and runs it on the vendored marked v18.0.14. The surviving inputs:

| input | output |
|---|---|
| `[a](jav&#x61;script:alert(1))` | `<a href="jav&#x61;script:alert(1)">a</a>` |
| `[a](&#106;avascript:alert(1))` | `<a href="&#106;avascript:alert(1)">a</a>` |
| `[a](javascript&colon;alert(1))` | `<a href="javascript&colon;alert(1)">a</a>` |
| `[a](java&#9;script:alert(1))` | `<a href="java&#9;script:alert(1)">a</a>` |
| `[a][r]` + `[r]: jav&#x61;script:alert(1)` | `<a href="jav&#x61;script:alert(1)">a</a>` |

Each decodes to a `javascript:` URL in the attribute. Python's `html.parser` gives `href = 'javascript:alert(1)'` for the first three. For `&#9;`, the URL parser removes the tab. The plain, mixed-case, `vbscript:`, `file:`, `data:`, autolink and plain reference forms render as text, as intended.

The scheme regex stops at `&`, so it finds no scheme and treats the href as relative. marked's `cleanUrl` is `encodeURI`, which keeps `&`, `#` and `;`. So on the served page, which holds the session token, one click on such a link in an item's document runs script there. The static page is affected too.

The spec can't see it, for three reasons:
- Its assertions are raw substring tests (`href="javascript:`, a `J…a…v…a…` regex), which an entity defeats.
- Its "disguised" fixture `[tabbed](java\tscript:alert(2))` is never a link token. marked renders it as text (`[a](java	script:…)`), so the control-character strip is never exercised. My X3 mutant (no strip) passes page.spec 9/0.
- My X2 mutant, a blocklist of `javascript|data` in place of the allow-list, passes page.spec 9/0.

So AC3's link clause is passed by the prototype, which leaves the hole, and by two other wrong implementations.
Critique: the tempting fix is to add `&` to the scheme regex, or to decode `&#…;` only. That still misses named references (`&colon;`, `&Tab;`, `&NewLine;`), and any future gap between what the renderer tests and what the browser parses. This is the same mechanism code review 001 F3 found (marked writes an href the page never checked), and the fix still judges one string while the browser parses another.
Consequences: if the page writes the anchor itself, what was tested is what the browser parses, but entity-encoded URLs that authors wrote on purpose (`?a=1&amp;b=2`) change meaning. If it decodes before testing, it needs every named reference, which needs the DOM or a table, and the node harness has a fake DOM. Autolinks and reference definitions go through the same renderer, so one fix covers them. Image `src` with `javascript:` doesn't execute in current browsers, so it needs no rule.
Recommendation: make the attribute hold exactly the string the test judged.
- In the `link` renderer, strip controls, then test the allow-list. On a pass, return `'<a href="' + esc(href) + '"' + (t.title ? ' title="' + esc(t.title) + '"' : '') + '>' + this.parser.parseInline(t.tokens) + '</a>'`, never `false`. `esc` escapes `&`, so `jav&#x61;script:` reaches the browser as the literal relative path `jav&#x61;script:…`, which is inert.
- State in §6 that character references in a link target are not decoded (a deliberate break from CommonMark).
- Page spec: put each of these in `LINKS`: `jav&#x61;script:`, `&#106;avascript:`, `javascript&colon;`, `java&#9;script:`, a reference definition with an entity, `JaVaScRiPt:`, `vbscript:`, `file:`, and a tab inside an angle-bracket destination (`[t](<java\tscript:alert(2)>)`, which marked does parse as a link).
- Assert on decoded attributes: HTML-unescape every `href="…"` in the pane, then require each one to have no scheme or an `http`, `https` or `mailto` scheme, with a URL-style strip of tabs and newlines first.
- Rows: X2 (blocklist), X3 (no strip) and "returns false for a passing link (marked writes the raw href)", each killed.
- Note the decode rule in zz-arch/links-in-rendered-documents-keep-a-scheme-allow-list, which today codifies the incomplete rule.
Lesson: z-design/spec-design-correspondence

### F2 [medium] The generation is read after `model()` yields, so a `gh` answer that lands during `engineHash()` labels the old PRs as current for a whole `gh` window
Where: serve.luau:402-414 (`model()` reads `gh.data` and lays each raft's `pr`/`checks`, then builds `m.live`, whose `stale = engineHash() ~= startHash` runs `git rev-parse` and yields); :470 (`local gen = \`{built}.{gh.version}\`` is read after `model()` returns); c0121.md:132 (§5, "a generation counter: rebuilds plus `gh` answers").
Evidence: `race.luau` uses synthetic stubs that yield as the real effects do: `gh` waits 0.02 s and `engineHash` waits 0.05 s, as `process.exec` yields. It polls `/api/state` every 0.1 s, then 31 s later:
```
old poll 2 live.checks ok R0001.pr 7      (and every later poll)
new poll 2 live.checks ok R0001.pr nil
new poll 3 live.checks ok R0001.pr nil
new poll 4 live.checks ok R0001.pr nil
new poll 5 (after 31 s) live.checks ok R0001.pr 7
```
Poll 1 read `gh.data` while it was still nil. `gh` then answered inside `engineHash()`, and `gen` became `1.1`, so the PR-less JSON was stored under the generation that has the PR. Every poll until the next `gh` answer (30 s later, and only while polled) serves "checks ok" with no PR, so the card says "no PR". The old per-poll encode healed this on the next poll.

The window per poll is the yield after the overlay: one `git rev-parse` per poll per tab, against a `gh` answer every 30 s. The real collect also yields, which is why poll 1 on the real tree had already seen the answer (`cpu.luau`). Those yields come before the overlay's read and are harmless.

None of the specs reaches this. Their `engineHash` stub doesn't yield, and `ghDelay` is 0 after the second case, so the stub answers synchronously.
Critique: the tempting fix is to compute `gen` before `model()`. That is safe in one direction (stale tag, fresh data, so one extra encode), but it splits the rule across two places. The real rule is that the tag and the data it names are read together.
Consequences: the generation must name what the overlay actually used. That also holds for `checks` inside `live`, but `live` is per poll and can't go stale. `act` and the `/` route call `model()` but never encode, so they are unaffected.
Recommendation:
- In `model()`, read `gh.version` and `gh.data` together, with no yield between them, and keep the overlay's version on the cache (`cache.ghVersion`). The splice keys on `{built}.{cache.ghVersion}`. Alternatively, compute `stale` and anything else that yields before the overlay, and say in a comment that nothing yields between the read and the generation.
- Server spec: an `engineHash` stub that yields (`task.wait(0.05)`) while a yielding `gh` stub answers inside it. Expect the poll after the answer to carry the PR.
- Row: "the generation is taken after a yield" (today's code), killed.

### F3 [low] G10's remaining CPU budget is not stated: the server still reaches the 1800 s limit after about two and a half days of one open tab, and a `gh` answer re-encodes even when nothing changed
Where: c0121.md:132 (§5), :153 (Scalability: "about 2.7 MB today", and a per-poll cost that leaves out the encode), :374 (G10); serve.luau:388 (`gh.version += 1` on every answer); zz-arch/per-poll-work-meets-the-cpu-limit (its check asks "how many requests does the process serve before its limit").
Evidence: measured on the real tree (`cpu.luau`): a steady poll costs 0.0028 s, a rebuild poll (build plus encode) 0.26 s, and one encode about 0.10 s (the old steady poll).
- While one tab polls: one rebuild a minute (the 60 s rule, more often while a raft commits or the dispatcher writes state), plus two `gh` answers a minute, each bumping the generation, plus 12 polls. That is about 0.26 + 2 × 0.10 + 12 × 0.003 ≈ 0.5 s of CPU a minute, which reaches 1800 s in about 60 hours.
- Before the fix it was about 1.46 s a minute, or 20 hours.
- `zn`:25-29 sets `ulimit -t` on the lune process, so the kernel kills the server, and the page then says "the server did not answer".

The body is 6.7 MB, not 2.7 MB.
Critique: the user chose "fix the cost only" and accepted a finite life, but the design doesn't say what that life is or what the person sees at its end. Two of the three encodes a minute come from `gh` answers that usually return the same PRs.
Consequences: bumping the version only when `gh`'s output text differs from the last answer is one string comparison. It removes about 40% of the remaining cost and changes nothing visible, because `checksAge` is in the per-poll `live` block.
Recommendation:
- Bump `gh.version` only when the output text or the error changed. Pin it with a server case: the same `gh` output twice gives no second encode.
- In §5 or Scalability, state the measured per-poll and per-minute cost, the resulting lifetime against 1800 s, and the symptom ("the server did not answer"; restart `./zn board --serve`).
- Correct the 2.7 MB.

### F4 [low] Stale statements after the second re-prep
Where:
- c0121.md:189 says "the code under test is carried unchanged onto `proto2-c0121`, so they were not rerun". `serve.plan`'s retry branch and the `/api/state` route changed in 4f879216, and the N rows on them (N11, N19 to N21, N40) now rest on the base runs above, not on a record.
- c0121.md:258, the table's preamble, says "N1 to N51 the first prep's, M1 to M13 the rebuilt one". N52 to N55 ran on proto2, and M1 to M21 per :189.
- c0121.md:94, §2, gives `serve.plan(…): (Plan?, string?)`. §4 (:120) says the function has three results.
- c0121.md:120, §4's stop bullet, says "409 here and 400 for every other refusal". The retry refusal is 409 too.
- c0121.md:153 has the 2.7 MB of F3.
- c0121.md:49, the Order paragraph, names only the first re-prep (G8). The second, G9 and G10, is in the rounds line and the Verification log only.

Evidence: each line was read against `git diff fa44f524 7bca94a6` and the table.
Critique: the executor and the code reviewer read these as the contract. A signature with two results and a "400 for every other refusal" invite a wrong `act`.
Consequences: none.
Recommendation:
- Rewrite each sentence: :189 "N52 to N55 ran on proto2; the earlier rows' cases are green on 7bca94a6"; the preamble; §2's three-result signature; §4's "409 for a stop with nothing running and a retry of a card that never ran"; Order, one clause for G9 and G10.
- Search for "unchanged onto", "2.7 MB" and "(Plan?, string?)" afterwards.
Lesson: z-design/restated-rules-move-together

## Lesson candidates (for the lead)
- zz-arch (links-in-rendered-documents-keep-a-scheme-allow-list), a note: test the string the browser will parse, not the token's raw text. marked writes the href without escaping `&`, so `jav&#x61;script:` passes a scheme test and runs. Write the anchor yourself with the escaped href, and pin entity forms with assertions on decoded attributes. Check: is the string my test judged byte-for-byte the attribute value after HTML decoding?
- zz-arch (per-poll-work-meets-the-cpu-limit), a note: a cache keyed on a generation counter must take the counter in the same step, with no yield, as the data the cached text was built from. Under Lune, any `process.exec` between the two lets a background task's answer re-label stale text. Check: between reading the data and reading the generation, does anything yield?

Verdict: changes
