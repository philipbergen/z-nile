# Review 001: R0006 (code mode)
Inputs: HEAD 673a805 against origin/main cb083de (`git diff origin/main...HEAD`), R0006.md, c0042.md, both check.sh files, c0042 acceptance specs, scripts/tracker/{board.luau,board.html,main.luau,store.luau}, scripts/lib/sh.luau, scripts/tracker.sh, scripts/vendor/*, tests/tooling/board.spec.luau, tracker skill row, SETUP.md row.

What I ran and confirmed:
- `scripts/check.sh --full`: GATE PASSED.
- `scripts/tracker.sh check c0042`: 6/6.
- `promote-check R0006`: OK.
- Two `tracker.sh board` runs on the real tracker are byte-identical (RC1).
- Sequestration: `git diff caa6d37 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty, and the start commit is a pure rename.
- `scripts/vendor/marked.umd.js` and `marked.LICENSE` are byte-identical to `package/lib/marked.umd.js` and `package/LICENSE` in `marked-18.0.14.tgz`. The sha256 matches the pin.
- Script-element safety: the inlined marked has one `<!--` (a regex literal) and no `<script` followed by a space, `/` or `>`, so the HTML tokenizer can't enter the double-escaped state. The JSON escapes `<`, so no data can end the `board-data` element.
- I loaded the real generated page in jsdom (a real HTML parser and DOM, with `closest`, `details` and `innerHTML`). A plain load works, and so do `#c0042`, `#r0060`, tab clicks, list-row clicks on a child span, pane links, and a link inside a `<summary>` (it jumps, and the details end up open and highlighted).
- `--open` with a failing opener prints the warning and exits 0.
- The tracker skill row and the SETUP.md row match the behaviour.
- Architecture: no change to `src/`. Performance: linear, and one pane is rendered at a time.

### F1 [medium] The page script throws on the search or hash values `constructor`, `__proto__` and malformed `%` escapes; on load this leaves the page blank
Where: scripts/tracker/board.html:142 (`var entry = model.home[q]`), :144 (`byId[entry].tab`), :179 (`decodeURIComponent(location.hash.slice(1))`)
Evidence: I ran the real generated page in jsdom:
- `#constructor` and `#__proto__` on load throw `TypeError: Cannot read properties of undefined (reading 'tab')`. `model.home` is a plain object, so `model.home["constructor"]` is `Object` and `model.home["__proto__"]` is `Object.prototype`. Both are truthy, and `byId[<function or object>]` is undefined. The list and pane stay empty (list children 0, no `h2`).
- `#%` and `#%E0` throw `URIError: URI malformed` before `switchTab`, with the same blank page.
- Typing `constructor` or `__proto__` in search and pressing Enter throws inside the listener. The field is never marked `miss`, so an unknown id gets no feedback.
`toString` and `hasOwnProperty` escape only because `go` lower-cases them. The same prototype lookup is in `idLink` through `byId[id] || issueById[id]`. There, `depends_on` values are `%w+` runs taken from documents, so `depends_on: [constructor]` renders "undefined" as the title.

I rate this medium, not high: the page never produces these inputs itself, and after a search-field error the arrow keys still work. But a blank page on load is a crash.
Critique: the tempting fix is `if (!entry || !byId[entry]) return false;` at :143. That covers `go` but not `idLink`, and not the `decodeURIComponent` throw, which happens before `go` is called.
Consequences:
- Every lookup keyed by user text or document text needs own-property semantics. Otherwise the next map added to the model (the Maintainability section plans review files and spend) brings the bug back.
- A malformed hash needs a defined outcome. The natural one is "no match": open on `initialTab`, as `#zzz` already does.
Recommendation:
- Add one helper, `function has(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }`, and use it for `model.home`, `byId` and `issueById` in `go` and `idLink`. Alternatively, copy each into `Object.create(null)` maps once at start.
- Guard the hash: `var start = ""; try { start = decodeURIComponent(location.hash.slice(1)); } catch (e) {}`.
- The sequestered smoke harness can't be changed, and node is already required by the gate. So add a node-driven case to `tests/tooling/board.spec.luau`: render a small fixture, then load it with `#constructor`, `#__proto__` and `#%`, each expecting the `initialTab` list rendered and no throw, and search `__proto__`, expecting `miss`. Only the DOM subset is needed, so a trimmed copy of the harness idea works.
- Add a row to c0042's Rules and mutants table, and a line to its Verification log: "non-id input to search or the hash is a miss, never a throw", killing the mutant "plain-object lookup".

### F2 [medium] The `--open` failure path (warn on stderr, still exit 0) is designed but untested
Where: scripts/tracker/main.luau:1060-1063; tests/tooling/board.spec.luau ("--open runs the opener …")
Evidence: the only `--open` case uses openers that succeed. Mutants that pass every spec:
- dropping the `pcall`, so a missing opener fails the command after the page is written;
- turning the warning into `fail(...)`;
- printing the warning to stdout.

The design requires "If that fails, print a warning to stderr: the command still succeeds, because the page was written". The Rules and mutants table has no row for it. I checked the behaviour by hand: `open` that exits 3 gives the warning on stderr and exit 0. So the code is right today, but nothing holds it.
Critique: the tempting fix is to copy the existing case with an opener that exits nonzero. That covers the nonzero exit but not "opener not found", which is a different path: `process.exec` throws, which is why the `pcall` exists.
Consequences: for "not found", the fake PATH must hide the real `open`/`xdg-open`, but still find `lune` and `bash`, which `tracker.sh` needs (tracker.sh prepends `~/.rokit/bin` itself). The case needs a PATH without `/usr/bin`, and it must stay portable to Linux runners.
Recommendation: add one case whose fake `open` and `xdg-open` `exit 3`. Assert `r.ok`, that the file is written, that `r.stderr` contains `warning:`, and that `r.stdout` is exactly the path line. Covering "not found" by reasoning in the Verification log is acceptable, since `pcall` around `process.exec` is the only thing between it and a crash. Add the matching Rules and mutants row.

### F3 [low] `board` argument handling: `--out --open` writes a file named `--open` in the repo root, and a positional path is silently ignored
Where: scripts/tracker/main.luau:1052, and `flags()` at :134-152
Evidence:
- `scripts/tracker.sh board --out --open` exits 0 and creates `./--open`, a 509 KB untracked file in the repo root, and no browser opens. `flags()` gives the next argument to any non-boolean flag.
- `scripts/tracker.sh board /tmp/x.html` prints `.cache/board.html` and never writes `/tmp/x.html`.
- `tracker.sh` changes to the repo root, so a relative `--out` from a subdirectory lands in the repo root, and the printed path is relative to a directory the caller isn't in. The design says so, but the printed path hides it.
Critique: the tempting fix is to special-case `--out` in `flags()`. That's shared by every command and changes its contract for the others (the Regression guard names it).
Consequences: validation inside `cmd.board` touches only this command. An `--out` value starting with `-` becomes an error, so a file literally named `-x` needs `./-x`, which is standard CLI convention. Printing an absolute path still satisfies AC3, whose spec matches the path as a substring.
Recommendation: in `cmd.board`:
- error with the usage line when `#pos > 0`, or when the `--out` value is empty or starts with `-`;
- print `process.cwd .. out` for a relative `out` (tracker.sh has already changed to the root);
- pass that same absolute path to the opener.
Add two tooling cases: positional argument refused, and `--out --open` refused, with no `--open` file created.

### F4 [low] Keyboard handling swallows browser shortcuts, and pane links can't be reached by keyboard
Where: scripts/tracker/board.html:152-161 and :77 (`idLink`)
Evidence:
- In jsdom, a keydown of `ArrowLeft` with `metaKey: true` gets `preventDefault` and switches Active to Done. So does Alt+←. Those are browser Back on macOS and on Windows/Linux, and with the page's own hash jumps a user reaches for Back. Ctrl+`/` is also swallowed.
- `<a class="jump">` has no `href` or `tabindex`, so Tab never reaches a Depends on or Dependents link, although the design calls the page "keyboard first".
Critique: the tempting fix is to add `href="#<id>"` alone. That fixes focus, but a click would then also navigate the hash and add history entries. The click handler's `preventDefault` stops that, so it's safe, but only while that handler runs first.
Consequences:
- AC6's harness matches `<a class="jump" data-id="R0002"` literally, so any new attribute must come after `data-id`.
- With a real `href`, middle-click and "copy link" produce `board.html#R0002`, which the on-load hash handling already serves. That's a gain, and it depends on F1's hash guard.
- Enter on a focused link fires `click`, so no new key code is needed.
Recommendation:
- Start the document keydown handler with `if (e.metaKey || e.ctrlKey || e.altKey) return;`.
- Emit `<a class="jump" data-id="X" href="#X">`, in that attribute order.
- Record both in the Verification log. OC1 covers the feel.

### F5 [low] Placeholder text in document prose, such as `<sha>` and `<y>`, disappears from the rendered pane
Where: scripts/tracker/board.html:113 and :116 (`marked.parse` output inserted raw)
Evidence: marked's lexer over the real tracker's bodies finds inline `html` tokens that aren't comments. In `tracker/issues/c0035/c0035.md:23`, "Review NNN started at <sha>" renders with `<sha>` parsed as an unknown element, so the text reads "started at". In `tracker/issues/done/f0011/f0011.md:87-95` the error-message specs show "row  has width" with `<y>`, `<x>` and `<c>` missing, so the documented message formats are wrong on the board. The other 372 html tokens are the templates' `<!-- … -->` comments, which should stay hidden.
Critique: the tempting fix is `marked.use({ renderer: { html: t => esc(t.text) } })`. That also escapes the comments, which would then show as literal `<!-- Module map … -->` text in every backlog raft.
Consequences:
- The renderer must hide comments and escape everything else. Documents lose intentional raw HTML such as `<details>` or `<br>` in prose. None use it today (the lexer found none), and escaping is also the safer default for a page with inlined data.
- `marked.use` runs once at page start, and the smoke spec's markdown table case is unaffected.
Recommendation: at the top of the page script, add `marked.use({ renderer: { html: function (t) { return /^\s*<!--/.test(t.text) ? "" : esc(t.text); } } })`. For the block case, keep the newline behaviour: escape `t.text` and let the paragraph flow. Add a tooling or harness-level case with body ``"at <sha> and `<code>`"`` that expects `&lt;sha&gt;` in the pane, plus a Verification log line. The alternative is a documented decision that placeholders in tracker docs must be backticked, but that belongs to the user, and the author must not decide it alone.

## Judged criteria (code mode only)
c0042 has no Judged criteria ("### Judged: None."), so there is nothing to rule on.

Verdict: changes requested
