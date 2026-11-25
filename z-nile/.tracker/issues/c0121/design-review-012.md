# Review 012: c0121 (design mode)
Inputs: prep-board-server2 30df1796 (`git ls-remote` agrees; c0121.md whole, check.sh, acceptance/ specs, overrides.sh, overrides.patch, harvest.md, the two lessons it edited, design-review-011 and design-refute-011, `git diff 80125e67 30df1796`); proto2-c0121 8ffccf92 (`git ls-remote origin refs/heads/proto2-c0121` → 8ffccf92…; `git diff 7bca94a6 8ffccf92`: serve.luau, board.html); origin/main f30d1d85 after `git fetch origin main`. Scratch clone `.worktree/prep-board-server2/.cache/r012/repo`, made by `/private/tmp/claude-501/-Users-philipbergen-code-pickman/1710de1d-709d-43fa-afde-dbe194852ce3/scratchpad/r012/setup.sh` (r011's script with PREP 30df1796 and tip 8ffccf92): `main` = origin/main plus the prep's c0121 folder, `raft` = main plus an empty start commit plus step 1's apply. Link probes: `scratchpad/r012/{cases.py,render.js,decode.py,judge.js}` (the page's own `marked.use` block on the vendored marked v18.0.14, attributes decoded by Python's HTML5 `html.parser`, each href resolved by node's WHATWG `URL`). Mutants: `scratchpad/r012/mut.py`. CPU probes: the clone's `z-nile/.cache/probe/cpu2.luau`. Every probe ran through `./zn run --time …`.
Round 2 of the second re-prep. Dropped from review-011: F1, F2, F3, F4 (each fix holds; the residue of F1 and F3 is below as new findings, not repeats).

## What holds (run)
- **Step 1 on today's main (f30d1d85)**: `merge-base --is-ancestor 8ffccf92 origin/proto2-c0121` succeeds; every non-new watched path exists and `serve.luau` does not; `git log --first-parent 3993dca2..origin/main -- <watched>` prints nothing; the apply exits 0 with every path clean; `git diff 8ffccf92 HEAD -- <8 paths>` is 0 lines; `overrides.patch` is byte-identical to the prototype's `docs.spec` diff, unchanged since fa44f524.
- **`./zn check c0121` on the replayed raft: 7/7** (AC7 green). **c0120 `check-paths.spec`** from the clone's `z-nile/`: 4 passed, 0 failed.
- **c0117's contract greps** on origin/main's `dispatcher.luau` (byte-equal to 3993dca2's, `cmp`): grep 1 `73: follows: string?` and `1848: st.follows = action.target`; grep 2 exactly line 986; grep 3 failed 8, lost 1, missing 1, stopped 1, tripwire 7, nil clears at 1790 and 2044.
- **The link renderer holds.** 89 inputs, `UNSAFE: 0`. Every entity form (`&#x61;`, `&#106;`, `&#0000106;`, `&colon;`, `&#58` and `&#x61` without semicolon, `&amp;#x61;`, `&#9;`, `&Tab;`, `&NewLine;`, a leading `&#x0a;`) reaches the browser as a literal relative path, because `esc` turns every `&` into `&amp;` (e.g. `href="jav&amp;#x61;script:alert(1)"`, decoded `jav&#x61;script:alert(1)`, protocol `http:`). Upper and mixed case, `data:`, `vbscript:`, `file:`, `blob:`, `filesystem:`, angle destinations holding a tab, `\x01`, `\x00`, `\x7f` or leading spaces, reference definitions, collapsed references, `<javascript:…>` autolinks, nested emphasis in the text, links in tables and task lists: all render as text. NBSP, U+2028, soft hyphen and BOM forms keep an href that the URL parser reads as relative (node `URL` agrees). Quotes in bare GFM URLs and in titles are escaped (`&quot;`). Raw HTML is escaped, and an html block starting with a comment is dropped whole (`<!---->x<script>` renders as ""). `![x](javascript:…)` keeps `img src="javascript:…"`, which does not run, as §6 says. The strip removes a superset of what the WHATWG parser ignores, so it can only refuse more. **`pr.url`** (board.html:296) is escaped but not scheme-checked; it comes from `gh pr list` (GitHub writes it, cross-repository PRs are skipped, serve.luau:236), not from document text, so it is no finding.
- **The generation fix holds.** In `model()` nothing yields between `local data = gh.data`, `local gen = …` and the overlay (serve.luau:410-417); `engineHash()` yields only after. With concurrent handlers on the shared cached model, a handler can encode data newer than its label (another handler overlaid newer PRs while the first waited in `engineHash`), never older: any overlay after a `gh` answer reads the new data. That costs one extra encode on the next poll. `m.live = nil`, the encode and the restore have no yield between them. Two concurrent rebuilds each pair their own `cache.model` with the `built` read right after (no yield). `act` passes `model()` in a non-final argument, so the second result is dropped.
- **The sig rule**: a failure, then a success, moves the version (the sig changes from `err:…` to the output). Two different failures move it (the error text differs), though the model is the same. Two unparseable outputs share one sig, also with the same model. A success repeated byte for byte does not move it.
- **Mutants** (base: page 9/0, server 25/0, guard 19/0):

  | mutant | result |
  |---|---|
  | N52 (renderer returns false) | page 8/1 |
  | N53 | page 8/1 |
  | N56 | page 8/1 |
  | N57 | page 8/1 |
  | N58 | page 8/1 |
  | X6 (href unescaped) | page 8/1 |
  | N54 | server 23/2 |
  | N59 (the `gen` read moved to the return, after `engineHash`) | server 24/1, on the yield case |
  | N60 | server 24/1 |
  | N61 | server 23/2 |
  | N55 | guard 18/1, server 24/1 |

  My first N59 spelling dropped `gen` altogether and crashed 11 cases, so it was not used.
- **Steady-poll cost**: 2.7 ms of CPU per poll ((2.05 − 0.41) s / 600 polls, the lune process's own `ps -o time`).
- **Scope**: Problem, title and Solution are unchanged since 80125e67.

### F1 [medium] The hand-written anchor's `title` escape is unpinned: a renderer that writes `t.title` raw passes page.spec 9/0 and gives an event handler to the served page
Where: board.html:167 (`' title="' + esc(t.title) + '"'`); page.spec.luau `LINKS` (:32-36: no link has a title) and the case at :210-232; c0121.md:328 (the row says "with its href escaped", nothing about the title); §6 (:139).
Evidence: mutant X7 replaces `esc(t.title)` with `t.title`. page.spec gives **9 passed, 0 failed**. The probe (`scratchpad/r012/x7`) renders `[a](https://ok.example "x\" onmouseover=\"alert(1)")` under X7 as `<a href="https://ok.example" title="x" onmouseover="alert(1)">a</a>`, and `judge.js` reports `EVENT a.onmouseover`. The reference form `[r]: https://ok.example "x\" autofocus onfocus=\"alert(1)"` gives `EVENT a.onfocus`. The prototype renders both as `title="x&quot; onmouseover=&quot;alert(1)"`, `UNSAFE: 0`. On the served page, hovering such a link in an item's document runs script that can read `model.live.token` and post Stop or Retry: the same harm as review 011 F1. The fix for that finding moved the anchor out of marked into hand-written code, and the spec pins only one of the two attributes that code writes.
Critique: the tempting fix is a title fixture plus a substring test for `onmouseover`. That misses the next attribute name (`onfocus`, `style`) and any later attribute the renderer gains.
Consequences: the fixture needs a title in both inline and reference forms, with a `"` in each. A check on the anchors' attribute set also catches an unescaped `"` that breaks out of the href. marked's own image renderer writes `alt` and `title` escaped already (probe: `alt="x&quot; onerror=&quot;alert(1)"`), so the same check can cover `<img>` as well.
Recommendation:
- Add to `LINKS` a safe link and a reference definition, each with a title holding `"` followed by an `on…=` text.
- In the link case, for every `<a …>` and `<img …>` tag in the pane, remove `href="[^"]*"`, `title="[^"]*"`, `src="[^"]*"` and `alt="[^"]*"` (plus `class`/`data-id` for the page's own jump links, if the pane has any), and require that nothing but whitespace remains.
- Assert that the title text survives, decoded, as the `title` attribute.
- Rows: X7 "the title written unescaped", killed. Extend the §6 rule and row :328 to "every attribute the renderer writes is escaped".

### F2 [medium] gh's version on a failure, and on a recovery to the same PRs, is unpinned: two wrong sig rules pass server.spec 25/0, and the failing-gh case passes only because a 60 s rebuild coincides with it
Where: serve.luau:389-394 (`local sig = if parsed then out else \`err:{gh.err}\``; the version moves when `sig ~= gh.sig`); server.spec.luau:474-482 ("a failing gh still gives 200, with checks unavailable", which asserts `R0020.pr == nil`); c0121.md:132 ("`gh`'s version moves only when its output differs from the last") and row :330.
Evidence:
- X11 (`if parsed and sig ~= gh.sig`: a failure never moves the version) gives server **25/0**.
- X12 (the sig remembers only successful output, and a failure always moves the version) gives server **25/0**.
- With `serve.REBUILD = 1e9` alone, only the 60 s case fails (24/1). With `REBUILD = 1e9` plus X11, "a failing gh still gives 200, with checks unavailable" fails too (23/2). So that case's `pr == nil` holds today only because the spec's `clock += 31` steps have added up to a model rebuild there, and the rebuild moves `built`.

Failure scenario under X11: `gh` answers PR #7 "passing", then fails (offline, token expired). `/api/state` keeps serving the cached JSON with #7 and "checks passing", while `live.checks` says "unavailable", until the next rebuild (up to 60 s). Under X12: success A, failure, success A again. The version does not move on the recovery, so the cached JSON from the failure (no PRs) is served with `live.checks = "ok"`, and every card says "no PR" until the next rebuild.

The rule the design states ("differs from the last", the last answer, errors included) is exactly what kills both, but no case reaches the transitions.
Critique: the tempting fix is one more `ghFails` toggle in the existing case. While the fake clock still adds up to 60 s, a rebuild lands in the window and hides the mutant again.
Consequences: each transition case must prove that no rebuild happened in its window (`builds` unchanged), which takes the case off the accumulated clock. That needs a key change just before it (`key = …`, which resets `cache.at`), so the 31 s steps start from a fresh build.
Recommendation:
- One server case, two steps, each of which starts from a fresh build so it stays inside one 60 s window:
  - **Failure step**: change `key`, poll and settle on answer A (assert #7). Then `clock += 31` with `ghFails = true`, poll, wait, poll. Assert `pr == nil`, `live.checks == "unavailable"` and `builds` unchanged since the settle.
  - **Recovery step**: change `key` again and settle (still failing). Then `clock += 31` with `ghFails = false` and the same A, poll, wait, poll. Assert #7, `live.checks == "ok"` and `builds` unchanged.
- At each step, assert both the PR the body shows and the number of builds.
- Rows: X11 "a failure never moves gh's version" and X12 "a recovery to the same output does not move it", each killed with `builds` held.

### F3 [low] The lifetime figures disagree with each other, and with a CPU-time measurement
Where: c0121.md:153 (Scalability): "a model build (about 0.5 s on the real tree, c0118)", and three sentences later "a model rebuild about 0.26 s every 60 s … about 0.3 s of CPU a minute … about four days".
Evidence: in the replayed clone, the lune process's own CPU (`ps -o time` of the probe's pid, which excludes git children, as `ulimit -t` does) gave:
- `rebuild 0` → 0:00.41;
- `rebuild 30` → 0:11.42, so 0.37 s per rebuild poll (build plus encode);
- `steady 600` → 0:02.05, so 2.7 ms per poll.

Host load was 17 to 23 on 18 cores. One tab costs 0.37 + 12 × 0.0027 ≈ 0.40 s a minute with no changed `gh` answer, so the 1800 s limit is reached after about 75 h (about three days), not four. Round 011's `cpu.luau` timed with `os.clock`, which in Luau is a wall-clock timer, so its 0.26 s depends on load (my run of the same probe gave 0.455 and 0.522 s). The 60 s figure is also a floor: any commit in any worktree, a fetch of origin/main or a dispatcher state write changes the key and forces a rebuild, so busy hours cost more. `parsePrs` on a real 138 KB `gh` answer is 2 ms, which is negligible.
Critique: the user accepted a finite life (G10), so this is a statement to correct, not a defect. But "four days" is the figure the user will plan by.
Consequences: none.
Recommendation:
- State the CPU-time numbers (rebuild about 0.3 to 0.4 s, steady about 3 ms) and the method (`ps` time of the server process, not `os.clock`).
- State the lifetime as "about three days with one idle tab, less while rafts commit or the dispatcher runs".
- Remove "about 0.5 s" or reconcile it with the rebuild figure.

### F4 [low] Stale statements after round 1
Where and Evidence:
- c0121.md:411 ends "Full gate on it: see the next entry.", and there is no next entry. The only full gate recorded on the second re-prep is :409's, on 7bca94a6, before review 011's code changes.
- c0121.md:178 ("Green on the prototype's full gate") does not say which tip.
- AC2 (:337) still says "encodes the model once per build and per `gh` answer". §5 (:132) and row :330 now say "per changed `gh` answer".
- c0121.md:189 says N1 to N51 "were not rerun". Their code includes `model()` and the gh task (N17, N19 to N21, N35), which 8ffccf92 changed (the second result, the sig). My `REBUILD = 1e9` run (N21's mutant) is still killed (24/1), so this is record-keeping only.

Critique: the executor reads the Verification log as the proof that the tip carried by step 1 passed the full gate.
Consequences: none.
Recommendation:
- Add the full-gate entry for 8ffccf92 (the author runs it), or drop the forward reference.
- Name the tip in :178, and align AC2's wording with §5.
- In :189, say which N rows ran again on 8ffccf92.
Lesson: z-design/restated-rules-move-together

## Lesson candidates (for the lead)
- zz-arch (links-in-rendered-documents-keep-a-scheme-allow-list), a note: once the page writes the anchor itself, every attribute it writes is the page's to escape, the title as well as the href. The spec pins the set of attributes that come out, not one attribute's scheme. Check: for each attribute my renderer writes, does a fixture put a `"` in it, and does the spec reject any attribute it didn't write?
- zz-test (a candidate, or a note on an existing fake-clock lesson): a case whose assertion a periodic rebuild can satisfy (a fake clock adding up across cases) must assert that the rebuild did not happen in its window. Check: if the cache's age rule were switched off, would this case still fail the mutant it names?

Verdict: changes
