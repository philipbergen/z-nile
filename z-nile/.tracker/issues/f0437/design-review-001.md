# Review 001: f0437 (design mode)
Inputs: origin/f0437-read 17a9e7916 (z-nile/.tracker/issues/f0437/f0437.md, "Slim design, step 6"; guesses.md G25 to G39; check.sh unchanged on the branch); main aae259463 (z-nile/app/live.js, z-nile/app/index.html, z-nile/engine/approvalfacts.luau, approval.luau, contract.luau, approvewalk.luau, themewrite.luau, store.luau, board.luau, z-nile/go/internal/web/web.go, approvals.go); real tracker and history, read only (probes in my own detached worktree's .cache, through ./zn run --time, live layer off).

Scope of this round: step 6 only. Slice tags: [S1] blocks slice 1 (markdown), [S2] blocks only slice 2 (index, links, detail), [S3] blocks only slice 3 (diff).

### F1 [high] [S1, S3] The walk shows a clipped piece of the approved `design` part, and both the markdown and the in-place diff are built on that piece without saying how much is missing
Where: Decisions 1 and 5 ("The page shows the idea and design as now, but with ins/del marks in place"); `approvalfacts.TEXT_CAP = 1500`, `approvalfacts.designParts` (only `## Design`), `ticketHtml` in live.js.
Evidence: The contract's `design` part is five sections (`contract.HEADS`: Problem, Solution, Design, Acceptance criteria, Test plan). The walk carries Problem and Solution cut at 1,500 bytes, the `###` parts of `## Design` cut at 1,500 each, and no Acceptance criteria or Test plan at all. Real numbers from `.cache/live/approvals.json`: c0306's doc is 90,804 bytes and the walk shows 4,430 characters. Its Test plan is 40,231 bytes and its Acceptance criteria 3,664, and the walk shows neither. c0249 has 11 of 21 parts clipped, f0417 15 of 22. The cut is shown only as a trailing `...`. Worse, **the common real change sits in the hidden text**: c0306's only change since its approval (+2 lines) is a `Decided with the user (2026-11-20)` line about 4,400 characters into its Problem, past the 1,500 cut. c0252, c0254 and c0394 have the same shape (a line appended to the Problem or Solution). In-place marks "on the design as now" have nowhere to go in the 7 small real cases E3 counts.
Critique: On an approval page this is text the owner approves without seeing, with no count. The renderer slice makes it worse, because rendered markdown looks complete. The tempting fix is to say "the in-place view uses the diff's own ops". That alone still leaves the unchanged 95% clipped, uncounted, and two whole sections invisible.
Consequences: To carry the full text, approvals.json must grow. All 13 waiting docs together are 1,333,937 bytes, which is under the 8 MiB `maxFacts`. That needs a total cap with its own counted notice, and Go's typed `approvals.go` structs must gain the new fields (it drops unknown ones). The page then renders up to about 140 KB per ticket on every repaint (see F13).
Recommendation: (1) Every contract section, Acceptance criteria and Test plan included, is shown in the walk, at least as a heading with its size. (2) Every clip says "first N of M characters; the rest: `./zn approve --show <id>`" (or the F7 command), with N and M from the engine (a `size` per part in the facts). (3) Decide the cap with the measured cost: whole sections for waiting tickets (1.33 MB today) under a total cap of, say, 6 MiB with a counted notice, or keep 1,500 and count. If the 1,500 clip stays, the owner should rule on it (escalate to the user), because it keeps most of every approved design off the page. (4) The in-place view is defined from the diff file (F3), never from the clipped approval text. Rows: a part over the cap shows "first N of M"; a ticket whose only change is past the cut shows it; Acceptance criteria and Test plan are listed; the Go reader passes `size` through.
Lesson: zz-arch/a-page-is-a-display-not-an-authority
Erred: z-design
Upstream: zz-review

### F2 [high] [S1] HTML comments are dropped silently, in the renderer and in the engine: contract text an executor reads, hidden from the approver, and a change inside one is unmarked
Where: Decision 1 ("HTML comments (`<!-- ... -->`) are removed first"), G28; `approvalfacts.designParts` (`string.gsub(doc, "<!%-%-.-%-%->", "")`).
Evidence: `contract.designText` keeps comments, so they are hashed and approved, and an agent executing the design reads them. A pushed `<!-- executor: also delete X -->` is approved unseen. In the diff, a changed comment gives "changed: design, +1" and the in-place view shows no mark. On real data, the 13 waiting tickets hold 9 comments today and all 9 are template comments (21 distinct template comments exist), so the cost of showing the others is zero today.
Critique: Dropping "the template's" comments is the intent. Dropping every comment is a hidden channel. The tempting fix is a count: "3 comments hidden". A count of hidden instructions is still unseen instructions.
Consequences: This needs one reader of "the template comments" (read from the templates, not a copy), used by approvalfacts and by the renderer. The engine changes in slice 1, so "No Go, no engine" no longer holds for slice 1 (see F18).
Recommendation: Drop only a comment that is byte-identical (whitespace-normalised) to a template comment. Show every other comment as a visible, labelled block ("a note hidden in the document:" plus its escaped text). In the diff, an op line inside any comment is always shown. An unterminated `<!--` stays text, as designed. Rows: a non-template comment shows; a template comment is dropped; a change inside a comment is marked in both views; the mutant "drop all comments" goes red.
Erred: z-design
Upstream: zz-review

### F3 [high] [S3] In-place rendering of elided ops fragments is undefined and loses or changes text
Where: Decision 5, `ops` ("the in-place view groups adjacent `-`, `+` lines into paragraphs and does a word diff in the page"), G35.
Evidence: Ops keep 3 lines of context and replace longer unchanged runs with `["~", n]`. A changed line inside a fenced block whose opener was elided is rendered as prose: `local x = a*b*c` becomes `a<em>b</em>c` and the asterisks vanish, and `# comment` in shell becomes a heading. A `+` fence opener whose closer was elided "runs to the end" and turns every later section into code. A changed table row without its header and delimiter rows becomes a paragraph of pipes. The order of "word diff" and "markdown" is unstated. If `ins` and `del` go into the source first, they split `**`, backticks and link syntax. If the markdown is rendered first, the word diff runs on HTML.
Critique: In a diff, text that changes when it is displayed is a wrong "what changed". The tempting fix is more context lines, which still cuts some block.
Consequences: Block context must come from the full old and new texts, which only the engine has.
Recommendation: The engine tags each op line with its block kind, computed on the full old and new texts (`fence`, `table` with its header line index, `prose`), and widens context to the start of the enclosing block (fence opener, table header and delimiter). The page renders `fence` and `table` op lines verbatim in monospace with line marks, and never as markdown. For a changed prose paragraph, the word diff runs on the source words and the paragraph is shown as escaped source with `ins` and `del` marks, with no inline markdown inside a changed paragraph. Unchanged context paragraphs render as markdown. Rows: a changed line inside an elided fence keeps its `*`, `#` and backticks; an added fence opener does not swallow later sections; a changed table row shows as a row; emphasis that spans a change keeps its characters.
Erred: z-design
Upstream: none

### F4 [high] [S1] AC3 to AC5 have no check lines, and the contrast check AC3 names is not a check
Where: Acceptance criteria (step 6), Checked AC3 to AC5; `z-nile/.tracker/issues/f0437/check.sh` (AC1 and AC2 only; the branch changes only f0437.md and guesses.md).
Evidence: `check.sh` runs the Go tests and `app-cli` plus `app-copy`. Nothing runs `app-md.node.js`, `units-facts`, `units-write`, `diff-since` or `approval-diffs`, and nothing checks "the contrast script reports 0 failures". The rules table says that script is "run once, result in the log".
Critique: A Checked criterion with no check line passes on any build. The tempting fix is to fold everything into AC2's `app-cli` run, which hides which slice's criterion failed.
Consequences: The new specs must exist (sequestered or promoted, and say which) before slice 1 starts, and they are then fixed for the executor.
Recommendation: Add one `check "AC3: ..."`, `"AC4: ..."` and `"AC5: ..."` line each, naming its specs. Make the contrast check a spec over the css tokens (light and dark, 4.5:1, and a non-colour carrier asserted), or move it to Observed. Mark the slice-3 real-queue proof as the check.sh-only line it is.
Erred: z-design
Upstream: none

### F5 [high] [S3] "The commit that added the last row" is searched by the current path, which a moved ticket defeats; reseals and promoted specs are not covered
Where: Decision 5 "What before is"; G33; E2 (the probe `before2.luau` has a glob fallback the design never states).
Evidence: Tickets move between folders. c0306's `approval.md` was added at `issues/c0306/` (1fe9e1fa6), renamed to `issues/active/c0306/` by `ready R0107` (d25a9373a) and renamed back by `stop R0107` (460cc5826). `git log -S<hash> -- <current path>` gives 3 hits there, while the glob `*/c0306/approval.md` gives 1. A ticket now in `active/` whose design changed between approval and `ready` gets the `ready` rename commit as its "oldest hit", whose text is the changed one, so it shows as `lost` ("earlier text not found") when it is recoverable. `approval.reseal` (d0298) rewrites the last row in place with new part hashes under the old when and who (renumber and compact), so the row's hash points at the reseal commit. `approval.partsOf(id, files, nil)` drops promoted specs when the commit's `acceptance/` is empty. Two rows: the last row is meant, which the design says, but no case pins it. Cost, measured: about 100 ms per ticket for `-S` with a glob pathspec over 3,477 commits, so it is bounded in practice. Safety holds: the hash is checked as 64 hex by `contract.parse`, the search is a fixed string, and any text accepted as "before" hashes to the recorded part, so tracker text cannot forge the before. It can only make it unfindable.
Critique: The sha check makes a wrong "before" impossible, but a false `lost` on the common lifecycle (approve, change, ready) is an unreadable common case.
Consequences: Taking any verified commit instead of "the commit that added the row" changes what `since.commit7` means: it is the commit the verified text was read from.
Recommendation: Use the pathspec `*/<id>/approval.md` across every project and state folder, passed as argv. Take every hit, newest first. For each part, accept the first commit whose part text hashes to the row's recorded part hash, with a bound such as 20 commits per ticket and the pass's 30 s. At that commit, read specs from the item's `acceptance/` or else from that commit's promoted folder (`projects.promotedDir`). `since` shows the row's when and who and the commit the text came from. Rows: approved in backlog, changed, readied (now `active/`) gives `ok`; a resealed row gives `ok` with the reseal commit; two rows use the last; one hash approved twice; specs found only promoted; a forged hit whose text does not hash gives `lost`.
Lesson: z-design/run-derived-answers-on-real-history
Erred: z-design
Upstream: none

### F6 [high] [S3] The 2,000-character line clip hides real changes
Where: Decision 5 ops ("a line clipped at 2,000 characters"), G34.
Evidence: Lines over 2,000 characters exist in 8 of the 13 waiting tickets (c0260 9 lines, longest 7,602; c0248 8 lines, longest 6,242; c0252 6 lines, longest 3,990; also c0250, d0331, c0254, f0417). These are long table rows and long `Decided with the user` lines. A change at character 2,500 of such a line shows a `-` line and a `+` line that look identical.
Critique: This shows a change as no change. The tempting fix is to raise the clip, which only moves the edge.
Consequences: none beyond the window rule.
Recommendation: For a changed pair, clip a window around the first and last differing character, with "N characters before or after not shown" on both lines. Context lines keep the plain clip with a count. Row: a 7,000-character line changed at character 5,000 shows the change.
Erred: z-design
Upstream: none

### F7 [high] [S3] Every cut, `bad`, `lost` and `skipped` state names a way out that does not work
Where: Decision 5 caps ("the rest: `git diff <commit7> -- <part>`, only as words (never a path)"), `bad`, G34, G36.
Evidence: (a) A part is not a path. The folder moves (F5), and the parts are canonical texts (`contract.canonCheck` rewrites `/issues/active/` and done paths, `normalize` folds CRLF), so `git diff <commit> -- <file>` shows a different diff from the contract's, or the whole file as new. (b) "Never a path" and `-- <part>` contradict each other. (c) For `bad` ("could not be matched"), `skipped: time` and capped parts, the owner has no way to see the changes at all. They can still approve, because `--apply` is hash-bound and the badge comes from the hashes, so the result is approval without seeing the change. Whether the four large real changes (c0250 +691 −139 in 7 parts, c0260 +879 −357 in 10, d0331 +381 −19, c0248 +871 −157, mostly new spec files) fit under 2,000 lines and 64 KB per part is not known until E10. A new spec file of about 800 lines at 80 characters is already 64 KB.
Critique: A cap is fine when what it cuts can be reached.
Consequences: One more read-only command, so one more CLI surface with tests, but no write.
Recommendation: Add `./zn approve --diff <id> [--part <name>]`: read-only, the same engine function, uncapped, unified. Every cut, `bad`, `lost` and `skipped` notice names it. A spec asserts its output equals the file's ops when nothing is cut. E10 records per-part bytes and lines for the four large changes and says which are cut and by how much.
Lesson: z-design/refusals-name-a-way-out-that-works
Erred: z-design
Upstream: none

### F8 [high] [S2] The units index misses real units and labels others wrong; the owner's own example c0261 can link
Where: Decision 3 (state `backlog|active|done`), E1 (460 units), E5, G29, G39; `store.all` (STATE_DIRS backlog, active, done only).
Evidence, measured: there are 473 unit documents on disk. `store.all` gives 460 and misses `rafts/retired/` (13 rafts: R0030, R0040, R0069, R0077, R0090, R0091, R0095, R0097, R0098, R0104, R0105, R0106, R0108; all 13 are mentioned in open documents). Those would get the tooltip "not in the tracker now (withdrawn, or an example)" though they are on disk. The board's model gives 453 (328 issues plus 125 rafts). It drops 7 closed tickets that sit in backlog folders with `status: closed-*` (c0141, c0224, c0268, c0407, c0408, d0400, d0401), which `store.all` counts as open backlog, so they are inside the designer's "169 open" and would get text and a "backlog" label. 239 matches none of the counts (473, 460, 453), and the design does not explain it. For the index, every document is the right set, and neither the board's model nor `store.all` gives it alone. Withdrawn tickets: `git log --diff-filter=D --name-only -- '*/.tracker/issues/*'` lists 96 deleted ticket ids in 0.18 s. Of the 77 mentioned ids missing on disk by my scan, 37 are withdrawn by that list, including c0261, c0123 and c0160, the three most mentioned. G29's evidence ("only 5 of the 78 have a withdraw commit subject") tested the subject line. The deletion commit is found by its diff, and one subject ("withdraw 72 z-nile backlog issues") covers 72.
Critique: The owner asked for "ids like c0261" to link. The design turns that example into plain text on wrong evidence. The 40 that remain (c9999, f0001, R0510 and so on) are examples, and plain is right for them.
Consequences: Two new state words reach the Go reader's known list, and the index gains stubs (id, date, commit subject: about 100 small rows).
Recommendation: States `backlog|active|done|closed|retired|withdrawn`. The index includes retired rafts (as `board.retiredOf` reads them, with their keeper) and closed tickets, labelled closed and without text. The engine adds withdrawn stubs from deletion commits (newest deletion per id; ids that later reappeared excluded). A link to a stub shows "withdrawn <date>: <commit subject>". G29 becomes this decision (it is not a cut). Rows: a retired raft links, a closed ticket is labelled closed, c0261 links to its stub, c9999 stays plain, and the Go reader accepts the new states.
Lesson: zz-test/seed-every-enumerated-case
Erred: z-design
Upstream: none

### F9 [medium] [S2] The units writer is a second reader of ticket documents, and its main-checkout guard sits in the callers
Where: Decision 3 "Written by `engine/unitswrite.luau` from `themewrite.refresh`"; E1's probe (its own `section()` parser); `themewrite.refresh`.
Evidence: `board.Model.issues[]` already holds `body`, state, raft and tributary for every issue, read once per refresh. The probe re-reads all documents (0.47 s per refresh) with its own section rule. `themewrite.refresh` has no main-checkout check: `cmd.board` and the approve path guard with `inMainCheckout()`, and `buildBoard(root)` calls it with whatever root it gets. `factsDir` honours an absolute `ZN_LIVE_DIR` from anywhere.
Recommendation: Build the index from the model the refresh already has (plus `board.retiredOf` for retired rafts). Take Problem and Solution through the contract's own section rule (export `bodyOf`) and Design through `approvalfacts.designParts`. Put the main-checkout check inside `unitswrite`. Rows: a refresh from a worktree with `ZN_LIVE_DIR` set writes nothing; the index's sections equal the approval facts' for a waiting ticket.
Lesson: zz-arch/one-reader-per-format
Erred: z-design
Upstream: none

### F10 [medium] [S1 for a, b, c, f; S2 for d, e] Gaps in the renderer's safety rules as written
Where: Decision 1 (element list, Links), Decision 2; live.js `link()`; index.html `applyRoute`.
Evidence and fixes:
- (a) The allowed list lacks `div` (the table scroll wrapper), `span` (the outside-address span, the visually hidden "added:" label) and the `title` on the missing-id mark. Either the allowlist test fails or it gets loosened ad hoc. List them, with their fixed classes and fixed texts.
- (b) The node "allowlist walker over the string" is not a browser parser. Building strings into `innerHTML` with `esc` is sound for this page (live.js does it throughout, and `esc` covers `& < > " '`), but the browser rewrites structure. Anything emitted inside `<table>` and outside a cell is foster-parented above the table, which reorders text. `<a>` inside `<a>` is split. An `<a>` inside the outline's `<button class="ap-o">` is nested interactive content. The walker must also check the content model: table children only thead, tbody, tr, th, td; no `a` inside `a`; no block inside `p`; no `a` inside `button`.
- (c) The Links bullet reads as a blocklist ("anything with a scheme") plus "an address that is an in-app route". Make it an allowlist. An href is built only from a route word in {ticket, raft, tributary, approvals} and an id that matches `ID_RE` or the raft shape and is in the index, or a name that matches `NAME_RE` and is in the themes facts (tributaries.toml is tracker text too). Every other `#/...` stays text, for example `#/guess/<id>/<x>`, which the mockup's `applyRoute` feeds to `$("#g-" + r.x)`, a selector that throws on `]`.
- (d) No id linking inside link text, inside a heading that is inside a button, or into any attribute.
- (e) `[c0250](c0306)` shows its target id beside the text when they differ.
- (f) The page already has an outside link: `link(tk.links.pr)` makes a clickable `https` anchor from the ticket's `pr:` front matter. That contradicts the owner's constraint and the design's "no outside link exists". Show it as text with a Copy button.
Rows for each, with mutants: the walker without the content-model check, `#/guess/` passed through, a link inside link text, the `pr:` anchor kept.
Lesson: zz-arch/links-in-rendered-documents-keep-a-scheme-allow-list
Erred: z-design
Upstream: none

### F11 [medium] [S1] The hostile and construct corpus misses cases that hide or change text, and some cuts hide where they should show
Where: Rules and mutants S1 rows; Decision 1 block rules; Bounds (e).
Evidence and required cases: a table row with more cells than the header (GFM drops the extras, so the text is hidden: show them); `\|` and `|` inside code spans in cells; CRLF and a lone CR (` ```\r ` is not a fence unless normalised first); tabs in list indents; fences indented inside list items (if they are not recognised, `#` lines in the code become headings); 4-space indented code (decide what it is); entities and numeric references (`&lt;`, `&#106;avascript:`: decide "shown literally", which is safe and matches the source); backslash escapes (decide); autolinks `<http://x>`; reference definitions `[1]: http://...` must stay visible, not be eaten; setext `text\n---` (the design says rule: pin it); an unterminated fence in a whole detail document; ids as `c0261's`, `(c0261)`, `c0261,`, `R0100/5/c0277`, `c0250-c0254`, `f0437-read`, `с0261` (Cyrillic с), ids in headings and table cells; U+200D inside emoji (decide). Cuts: table rows past 200 and columns past 40 must show the rest as escaped text, as the budget exit does, not be "cut with the same cut notice". The 200-character clip of an outside address hides part of what the owner may copy: show it whole, wrapped. Budget coherence holds on real data: walk and index texts are at most 1,500 per part today and diff ops at most 64 KB, so the 200,000-character and 2,000,000-step bounds bind only on hostile text.
Erred: z-design
Upstream: none

### F12 [medium] [S1] Real-data proofs test the wrong input, one has no independent oracle, and the timing assertions will flake
Where: Rules S1 "the real tickets", S2 "real ids", S1 "huge" (250 ms), G27.
Evidence: S1 renders raw `.md` sections. The page gets the engine's JSON through the Go reader: clipped with `...` in the middle of constructs, comments stripped, lists that may arrive as `{}`. Both real-data failures today were on that chain. S2's "exactly those whose unit exists in the real index link" is computed from the same index and boundary rule it tests. 250 ms wall-time assertions in a gate spec flake under load. The owner's rule: real-work proofs are one-time check.sh lines; gate specs are fast and deterministic.
Recommendation: For each slice, one check.sh-only chain proof on the real tracker: the engine writer goes to a throwaway `ZN_LIVE_DIR`, the Go reader serves it, and the page renderer runs over the served JSON in node. The gate keeps a frozen fixture copied once from that real output. Assert step counts in the gate, and keep a wall-time ceiling of about 5 s only as a hang guard. S2 gets an oracle independent of `linkIds`: frozen expected counts for the fixture, plus named cases.
Erred: z-design
Upstream: none

### F13 [medium] [S2, S3] Every daemon event refetches up to 1.6 MB and repaints everything, wiping the reader's place
Where: Decisions 3 and 5 (fetch policy unstated); live.js `refresh` → `refreshApprovals` → `paintApprovals` (innerHTML of the whole view on every event and every 15 s).
Evidence: Adding `/api/units` (317 KB) and `/api/approval-diffs` (up to 1 MB) to that path means every heartbeat-driven event re-downloads them, re-validates them in Go, re-renders markdown and re-runs the word LCS. Expanded sections, the selection and the switch state are lost on each repaint unless they are kept outside the DOM. The node tests pin the fetch list (`app-live.node.js`: "http: state is fetched" expects exactly `/api/state`; "the Approvals view is not fetched before it is shown"; "themes: showing it fetches /api/themes only").
Recommendation: Fetch units only when their poke (`units`) arrives or on first need. Fetch diffs together with approvals, on the approvals poke. Memoise rendered HTML by text hash. Keep the expand and switch state keyed by ticket and section, and keep the scroll position. Name which node checks change and to what.
Erred: z-design
Upstream: none

### F14 [medium] [S2] Routing and Back cases are missing
Where: Decision 4, G30, G37, E9.
Evidence: (a) A link to `#/approvals/<id>` for a ticket outside the current theme filter (`AP.theme`) is not in `apList`, so it lands on index 0 silently. (b) Back fires `applyRoute`, which sets `scrollTop = 0`: the owner returns to the ticket but at the top of a 100 KB design. (c) `R.badge` says "simulated" for every view except Workers, Approvals and Themes, so the real detail view would be labelled simulated. (d) The detail view's crumbs (the mockup's `#/tickets`) lead to the simulated list with mockup ids. (e) A route id for a ticket that no longer waits needs words.
Recommendation: Clear the filter (or say "c0250 is outside theme X: show it") for (a); restore scroll per route in page memory for (b); a badge rule for detail routes for (c); no link to simulated views from real ones for (d); and "c0250 no longer waits" for (e). Cases for each in `app-live.node.js`, which E9 then confirms in the real page.
Erred: z-design
Upstream: none

### F15 [medium] [S3] The diff file's binding to the queue can show a diff of other text, or a message no command clears
Where: Decision 5 ("Written atomically in the same `--queue` call, before the approval facts, in its own pcall"), G38, decision 6 point 5.
Evidence: (a) If `approvaldiffs` reads the files again instead of using the parts the queue hashed, a fast-forward of main in between (a `./zn sync` in another session) gives a diff of other text under the queue's hash. (b) If the whole pass fails, the earlier file keeps its old `run`, and the page says "made for another run: run ./zn approve --queue" forever, because rerunning fails the same way. (c) When the page fetches the diffs is unstated. (d) Point 5 and "open question 3" leave the terminal count undecided.
Recommendation: Compute from the same gathered parts, and recompute and compare the hash per ticket before writing. On a whole-pass failure, write `{version, run, state:"failed", why}` (or remove the file, as the approval facts do), and the page says why. Fetch the diffs with the approvals. Decide now that `--apply` prints the same one-line count per ticket ("changed: design, 2 sections, +14 −6"): it is cheap and closes the residual risk. Rows for (a), (b) and the count.
Lesson: zz-arch/read-paired-facts-at-one-moment
Erred: z-design
Upstream: none

### F16 [medium] [S3] The contract's `risk` part has no diff kind, and the guesses' display contradicts itself
Where: Decision 5 parts (`kind: prose|code`), display; `contract.build` (`parts.risk`, c0435).
Evidence: A ticket whose `risk:` changed has a `risk` part with no kind, so it is either a crash or `bad`. Guesses are "code-like ... unified only, may be switched to nothing else", and in the same paragraph "a guess card whose line is `+` shows new since your approval; a changed one shows its words struck and added".
Recommendation: Kinds: `design` is prose; `check.sh` and specs are code; `guesses` shows per-guess cards in place, with a unified switch; `risk` is one value shown as "risk: normal → risky". Add a row with a risk change.
Erred: z-design
Upstream: none

### F17 [medium] [S1] The open questions the design cites do not exist in the document
Where: E5 ("See open question 1"), decision 6 point 5 ("open question 3"), `## Open to the human: none`.
Evidence: No numbered open-question list exists in the issue. My ruling on the two that are cited: Q1 (withdrawn ids) the design should simply decide, as F8 says, because it is cheap and measured. Q3 (the terminal prints the count) the design should simply decide yes (F15). The real owner decisions are: how much text the walk carries (F1: the 1,500 clip against whole sections at about 1.33 MB), and whether the `pr:` link stops being clickable (F10 f), since that removes a working click.
Recommendation: Put the remaining owner questions under `## Open to the human` as guesses with options and costs, and remove the dangling references.
Erred: z-design
Upstream: none

### F18 [low] [S1, S2] Touched modules, watch files and the slice-1 size are incomplete
Where: Touched modules, Affected specs, Slices.
Evidence: `app-cli.watch.txt` names every Go source by file, so new `units.go` and `diffs.go` must be added there and to the live-cli, live-autostart and livecall watch files, or the affected selector skips the specs. Also missing: `approvalfacts.luau` and `approvals.go`'s typed structs for F1 and F2 (Go drops unknown fields, so any added field needs the struct); `contract.luau` (an exported section reader, F9); `main.luau` (`--diff`, F7); `board.luau` (`retiredOf`, F8). Slice 1 therefore touches the engine and Go (about +150 lines). The other sizes are believable. No promoted acceptance spec is changed: the route-set and fetch checks are tooling tests and the Go tests under AC1, so no `Overrides:` line is needed. Name the tooling checks that change (F13).
Erred: z-design
Upstream: none

### F19 [low] [S2] The missing-id tooltip states a fact the page cannot know
Where: Decision 2, G29; Decision 3 "a failed write leaves the earlier file".
Evidence: When a units write fails, the index stays old, and a new ticket's id gets "not in the tracker now".
Recommendation: Use "not in the units index made <age> ago", from `at`.
Erred: z-design
Upstream: none

### F20 [low] [S3] Collapsed and renamed sections, and the Judged rubric's examples
Where: G35, JC1.
Evidence: An unchanged section expands to 1,500 characters without "of N". A heading renamed by one word becomes a whole section removed plus a whole section added. JC1 names c0306 and c0250, which will likely be approved before slice 3 lands.
Recommendation: Say "first 1,500 of N characters" on expand. Pair a lone removed section with a lone added section at the same position as "renamed". In JC1, use "the waiting changed-design tickets with the smallest and the largest diff when slice 3 is judged".
Erred: z-design
Upstream: none

Blocking summary: slice 1 can start after F1 (only the clip counts and the listed sections; the text-cap ruling may follow), F2, F4, F10 (a, b, c, f), F11, F12 and F17. Slice 2 also needs F8, F9, F10 (d, e), F13, F14 and F19. Slice 3 also needs F1 (the in-place source), F3, F5, F6, F7, F15, F16 and F20.

Verdict: changes
