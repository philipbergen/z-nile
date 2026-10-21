# Review 015: R0042 (design mode)
Inputs: prep-z-nile at 9fed9c6 (R0042.md, check.sh, harvest.md, design-review-014 and design-refute-014, skimmed 006 to 013; c0111 and c0119 documents, check.sh files and acceptance specs; the diff e5f671e..9fed9c6). The prototype `.worktree/proto-scope-fidelity`: both issue folders are identical to this tree (`diff -r`). I read its `cmd.metrics` (`metricsLessons`, `addedAt`), `lessons.day`, `lessons.roundsSplit` and `stats.luau`'s day helpers.
Round 014's F1 and F2 are answered: metrics no longer reads history, so a compaction can't misdate a raft, and ready-raft and item 11 name all three markers, pinned in `scope-docs.spec`. I don't reopen either, or the user's decisions (read-only `capture`, Luau on Lune, "Never cross; mark it").

Run on the prototype:
- c0111's and c0119's acceptance specs: `65 passed, 0 failed, 11 spec files`.
- `luau-lsp analyze` of `scripts/tracker` and both acceptance folders: exit 0.
- `lessons --check`: `21 lessons, 108 harvest entries, ok`. `--uncovered R0042`: covered.
- `tracker.sh metrics`: `before | 41 | 174 | 4.2`, `after | 0`.
- `capture c0111` and `capture c0119` (both unmarked).
- A mutant in a scratch copy (`.../scratchpad/review015/m1`, a plain copy of the prototype with its own repository): `local added = os.time()` in `metricsLessons`. Result: `5 passed, 0 failed`.

I didn't run `promote-check`.

Lessons pass (item 10, `lessons --when design --full`):
- Failed: `testing/pin-call-site-arguments` and `ticket-prep/spec-design-correspondence`. The new fixture can't show a wrong cutoff (F1).
- Failed: `ticket-prep/spec-design-correspondence` and `ticket-prep/restated-rules-move-together`. AC9's text describes a fixture that was removed, and three passages still say metrics reads the trail (F2).
- Failed (low): `architecture/one-reader-per-format`. `lessons.day` duplicates `stats.luau`'s day parser, and it reads `created:` as UTC although `tracker.sh new` writes the local date (F3).
- Passed or not applicable:
  - `tracker/item-history-spans-moves-and-compaction`: the dater uses no history and no `--follow` across items. The cutoff's `--follow` runs on one unique file.
  - `seed-every-enumerated-case`: the fixture seeds three rafts and a compaction-like rewrite.
  - `no-vacuous-pass`: AC9 asserts exact rows.
  - `exhaustive-lists-name-new-things`: all three markers are named.
  - `new-rules-migrate-existing-work`: all 41 real rafts have a `created:` day.
  - `never-narrow-captured-scope` and `no-scope-cut-as-fix`: item 11 below. No Recommendation here cuts.

Scope fidelity (item 11, against the prototype's `capture`):
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`, unmarked). Diffing everything before `## Design` against the capture shows three changes:
  - the four `Scope decision` lines;
  - the rewritten Non-goals. No captured outcome moved into them: seeding is c0112 by decision, and code-review harvest is in scope;
  - the `As designed` paragraph.

  The captured Solution bullets are verbatim. Every outcome has a Design and a criterion. The captured **metrics** outcome ("show whether lessons reduce review rounds") rests on AC9, and F1 shows that AC9 doesn't pin the cutoff that the split depends on.
- c0119 (`ab750c0`, unmarked): the diff against the capture is exactly the `Decided with the user (2026-10-20)` block. AC1, AC2 and AC4 cover the rules and the command.

### F1 [high] AC9 passes when the reader takes the cutoff from the wrong place (the clock, HEAD, the first commit): the new fixture makes the lessons.luau add day equal to today
Where: c0111 Metrics, **The reader** ("The cutoff is the UTC day of the oldest `git log --follow --diff-filter=A …` line"); Rules row "the reader takes the cutoff from lessons.luau's add commit | … | pass no cutoff"; `metrics-lessons.spec` "tracker.sh metrics prints the tag table, and dates rafts by their created day".
Evidence:
- **The fixture's dates.** `trackerfix.new` commits the seed, which holds `scripts/tracker/lessons.luau`, at the current time, and the compaction-like commit is also made now. So the true cutoff is today. The rafts are created on 2099-01-01 (R0010, R0020) and 2020-01-01 (R0030). Any cutoff between 2020 and 2099 gives the same table: `before | 1 | 2`, `after | 2 | 3`.
- **The mutant survives.** I replaced `addedAt("scripts/tracker/lessons.luau")` with `os.time()` in a scratch copy of the prototype. `metrics-lessons.spec` printed `5 passed, 0 failed`. HEAD's commit day, the seed's (first) commit day and `lessons.luau`'s newest add also pass, because they are all today.
- **The previous fixture killed it.** Before this round, R0010's and R0020's reviews landed in the seed. A "now" cutoff put them before, against the expected `after | 2`. Round 014's answer moved the discrimination into far-off `created:` days and lost it.
- **On the real tree, these mutants give a wrong table.** With `os.time()`, every raft created before the day you run the command counts as before, forever. With HEAD's day, the same happens. The captured outcome ("to show whether lessons reduce review rounds") then never shows an "after" column. The only listed mutant, "pass no cutoff", is the one the fixture still kills.

Lesson: testing/pin-call-site-arguments
Critique: The cutoff is an argument the call site computes. The fixture masks a wrong value, because the true value and every plausible wrong value are the same day. The tempting fix is a pure `roundsSplit` case with a different cutoff number. That proves nothing about where the reader gets the number.
Consequences: making the add day differ from today, HEAD and the first commit means rewriting the fixture's own history in `f.main` (still under `.cache/`, as `@example.invalid`). That clone then diverges from `origin`. `metrics` reads only HEAD, so nothing else changes. It also lets the CLI case cover the `>=` boundary on real days. I tried the recipe below in the scratch copy. The intended reader passed 5/5, and the `os.time()` mutant failed (`4 passed, 1 failed`).
Recommendation:
- In the CLI case, before the compaction-like commit:
  - `git rm -q --cached scripts/tracker/lessons.luau`, then `git commit -q --amend --no-edit` with `GIT_COMMITTER_DATE`/`GIT_AUTHOR_DATE` set to `2020-01-01T00:00:00Z`;
  - `git add scripts/tracker/lessons.luau` and commit it with the date `2030-06-01T12:00:00Z`.
- Create the rafts so that each side of the cutoff is tested:
  - one on 2030-05-31 (before, the day before the cutoff);
  - R0010 on 2030-06-01 (after, at the cutoff);
  - R0020 on 2099-01-01 (after);
  - R0030, which kills history dating, can be the 2030-05-31 raft.
- Expected rows: `before | 1 | 2`, `after | 2 | 3`, as today.
- Add the mutants to the Rules row and kill each one:
  - cutoff from `os.time()`;
  - cutoff from HEAD's commit time;
  - cutoff from the repository's first commit;
  - strictly-after at the reader.
- Record the run as an E-entry.

### F2 [medium] AC9's text describes a case the spec no longer has, and three passages still say metrics reads the trail
Where:
- c0111 Acceptance criteria, AC9: "A raft whose first review is backdated, deleted, written again to equal another raft's, and moved into `done/` counts as before."
- The trail, first paragraph: "c0111's metrics reader uses it". This contradicts the same section's "**Metrics** does not use the trail".
- Implementation step 7: "with the reader on the trail".
- Metrics Output: "`Design rounds before and after lessons (cutoff: the commit that added scripts/tracker/lessons.luau).`". The prototype prints "(a raft's created day against the day scripts/tracker/lessons.luau was added)", and no spec pins the heading.
- Test plan line for `metrics-lessons.spec` (no `day` case named).
Evidence: round 014's answer deleted the backdated, deleted and re-added R0030 from `metrics-lessons.spec` (see the diff e5f671e..9fed9c6). AC9 still promises that scenario, and it doesn't state the rule the spec now checks (dating by `created:`). An executor following step 7 builds the reader on the trail, which is the design round 014 removed. Only the spec, not the document, stops them.
Lesson: ticket-prep/spec-design-correspondence
Recommendation:
- Rewrite AC9 to say what the case checks: rafts are dated by their `created:` day against the day lessons.luau was added, at-or-after is after, and a rewritten review file doesn't change a raft's date. After F1's fix, add "with a cutoff that differs from today and from HEAD".
- Fix The trail's first paragraph (only `capture` uses the trail) and step 7 (the reader reads `created:`).
- Pick one Output heading and make the prototype print it. Optionally pin it with `has(r.stdout, …)`.
- Add the `day` case to the Test plan.

### F3 [low] `lessons.day` is a second copy of `stats.luau`'s day parser, and it reads `created:` as UTC although `tracker.sh new` writes it in local time
Where: c0111 Metrics, **day** ("days since 1970-01-01 in UTC"); `scripts/tracker/stats.luau` `parseDay`/`daysFromCivil`/`toDays` (local, same algorithm); `scripts/tracker/main.luau:83` `os.date("%Y-%m-%d")` (local) writes `created:`, while the cutoff is `math.floor(%ct / 86400)` (UTC).
Evidence: a raft created at 20:00 PDT on the day lessons land (03:00 UTC the next day) gets `created:` set to the PDT date, while the cutoff is the next UTC day, so the raft counts as before. This affects only a raft created within hours of the cutoff, and the Design already accepts day granularity. `stats.luau` says "Dates are civil days … never os.date", so the tree already has one day reader.
Lesson: architecture/one-reader-per-format
Recommendation: export `stats.toDays` (or move it to a shared helper) and call it from `lessons.day` instead of a second copy. In Metrics, say that `created:` is the author's local day and the cutoff is a UTC day, so a raft created on the cutoff day can fall either side.

Verdict: changes
