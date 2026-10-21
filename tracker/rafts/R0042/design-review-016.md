# Review 016: R0042 (design mode)
Inputs: prep-z-nile at 84dd223: R0042.md, check.sh, harvest.md; design-review-015 and design-refute-015; 006 to 014 skimmed; c0111's and c0119's documents, check.sh files and acceptance specs; the diff 9fed9c6..84dd223. The prototype `.worktree/proto-scope-fidelity`: both issue folders are identical to this tree (`diff -r`). I read its `cmd.metrics` (`metricsLessons`, `addedAt`), `lessons.day` and `stats.day`.
Round 015's F1, F2 and F3 are answered. The cutoff now comes from a 2030-06-01 add, so the clock, HEAD and first-commit mutants fail. AC9, The trail, step 7, the Output heading and the Test plan now agree. `lessons.day` delegates to `stats.day`. I don't reopen any of these, or the user's decisions (read-only `capture`, Luau on Lune, "Never cross; mark it").

Run on the prototype:
- c0111's and c0119's acceptance specs: `65 passed, 0 failed, 11 spec files`.
- `luau-lsp analyze` of `scripts/tracker` and both acceptance folders: exit 0.
- `tracker.sh metrics`: `before | 41 | 175 | 4.3`, `after | 0 | 0 | 0.0`.
- `capture c0111` and `capture c0119`: both unmarked.
- `metrics-lessons.spec` with `TZ=Pacific/Auckland`: `4 passed, 1 failed` (F1).
- I made a scratch copy at `.../scratchpad/review016/m1`, a plain copy with its own repository:
  - The UTC mutant, `os.date("!%Y-%m-%d", added)`: `5 passed, 0 failed`.
  - With the recipe in F1's Recommendation, the UTC mutant fails (`4 passed, 1 failed`). The intended reader passes 5/5 with the host TZ unset, and set to Pacific/Auckland, UTC, Pacific/Kiritimati and Pacific/Pago_Pago.

I didn't run `promote-check`.

Lessons pass (item 10, `lessons --when design --full`):
- Failed: `testing/pin-call-site-arguments`. The cutoff's time zone is part of the argument the call site computes. The host's zone hides a wrong value, and in zones of UTC+12 or more it also breaks the correct one (F1).
- Failed (low): `testing/seed-every-enumerated-case`. Every metrics fixture raft is in the backlog, so a reader that skips `done/` passes (F2).
- Failed (low): `ticket-prep/restated-rules-move-together`. A spec comment and a case title still describe the old fixture and the old UTC rule (F3).
- Passed or not applicable:
  - `spec-design-correspondence`: AC9, the Test plan and the Output heading match the spec and the prototype.
  - `item-history-spans-moves-and-compaction`: rafts are dated by `created:`. The one `--follow` runs on a single unique module path.
  - `one-reader-per-format`: `lessons.day` uses `stats.day`.
  - `no-vacuous-pass`: AC9 asserts exact rows.
  - `new-rules-migrate-existing-work`: all 41 rafts are dated.
  - `exhaustive-lists-name-new-things`: `stats.luau` is in Touched modules.
  - `never-narrow-captured-scope` and `no-scope-cut-as-fix`: see item 11 below. No Recommendation here cuts anything.

Scope fidelity (item 11, against the prototype's `capture`):
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`, unmarked). Before `## Design`, three things differ from the capture:
  - the four `Scope decision` lines;
  - the rewritten Non-goals, into which no captured outcome moved;
  - the `As designed` paragraph.

  The captured Solution is verbatim, and every outcome has a Design and a criterion. The captured metrics outcome rests on AC9, which F1 strengthens.
- c0119 (`ab750c0`, unmarked): the diff against the capture is exactly the `Decided with the user (2026-10-20)` block. Same as round 015.

### F1 [medium] The new "local calendar day" cutoff isn't pinned, and its fixture fails on a machine at UTC+12 or more: the lessons commit is dated 2030-06-01T12:00:00Z and read in the host's zone
Where: c0111 Metrics, **The reader** ("The cutoff is the local calendar day … of the oldest `git log --follow --diff-filter=A …` line"); Rules row "the cutoff is the day `lessons.luau` was added" (mutants: the clock, HEAD's commit, the first commit); `metrics-lessons.spec` "tracker.sh metrics prints the tag table …" (`at("2030-06-01T12:00:00Z")`, `trackerfix.tr(f, f.main, { "metrics" })` with no env).
Evidence:
- **The rule is unpinned.** Round 015 F3's answer made the cutoff the local day of the commit, so that it matches `created:` (`os.date("%Y-%m-%d")`). At 12:00Z the UTC day and the local day are the same in every zone from UTC-12 to UTC+11. The mutant `os.date("!%Y-%m-%d", added)`, which reverts to the UTC rule this round replaced, printed `5 passed, 0 failed` in the scratch copy.
- **The correct reader fails in some zones.** On the unchanged prototype, `TZ=Pacific/Auckland lune run tests/run -- …/metrics-lessons.spec.luau` gave `4 passed, 1 failed` at line 143 (`after | 2 | 3`). In NZST, 12:00Z is 00:00 on 2030-06-02, so R0010 (created 2030-06-01) counts as before.
- **The failing file is sequestered.** The executor can't fix it, and `done`'s full gate is red for anyone in New Zealand, Fiji or Kiribati. CI (UTC) passes.
Lesson: testing/pin-call-site-arguments
Critique: the zone the cutoff is read in is part of the value the call site computes. The fixture neither fixes that zone nor picks an instant whose UTC and local days differ, so a wrong zone is invisible and the right zone is host-dependent. The tempting fix is to move the instant to 2030-06-01T00:00:00Z or similar. That only changes which zones fail, and the UTC mutant still survives in most of them.
Consequences: pinning `TZ` for the `metrics` process makes the case independent of the host. The commit instant has to be written with an explicit offset, so git stores the same timestamp everywhere. The design should then say that "local" means the zone of the process that runs `metrics`. Someone who writes a `created:` day in another zone can land one day off, which day granularity already accepts. Nothing else reads the cutoff.
Recommendation:
- In the CLI case, date the lessons commit `at("2030-06-01T20:00:00-07:00")`. That is 2030-06-02 in UTC.
- Run `trackerfix.tr(f, f.main, { "metrics" }, { TZ = "America/Los_Angeles" })`.
- Expected rows are unchanged: `before | 1 | 2`, `after | 2 | 3`.
- I ran exactly this in the scratch copy. The intended reader passed 5/5 under five host zones (unset, Pacific/Auckland, UTC, Pacific/Kiritimati, Pacific/Pago_Pago). The UTC mutant failed (`4 passed, 1 failed`), as do the three existing cutoff mutants (2030 is far from the clock and from the fixture's other commits).
- Add "the UTC day of the commit" to the cutoff row's mutants.
- State in Metrics that the cutoff and `created:` both use the zone of the running process (`TZ`).
- Record the run in E10.

### F2 [low] Every metrics fixture raft is in the backlog, so a reader that skips `rafts/done/`, where nearly all real rafts live, passes AC9
Where: `metrics-lessons.spec` CLI case (R0010, R0020 and R0030 are all under `tracker/rafts/<id>/`); c0111 Metrics, **The reader** ("For each raft with a design-review file").
Evidence: the prototype uses `store.all("raft")`, which walks every state, and that is correct. But nothing in the spec distinguishes it from a hand-written `fs.readDir("tracker/rafts")`, which would drop `done/`. On the real tree, that mutant would date only the backlog and `active/` rafts. This is reasoned: the fixture holds no `done/` raft, so the case can't fail for it.
Lesson: testing/seed-every-enumerated-case
Recommendation:
- Seed R0030 (the before raft) under `tracker/rafts/done/R0030/` and R0020 under `tracker/rafts/active/R0020/`. Their ids still count, and the expected rows stay the same.
- Add the row "the reader walks every raft state | metrics-lessons :: tracker.sh metrics prints … | read only `tracker/rafts/`".
- The Design sentence can then say "every raft (`store.all`)".

### F3 [low] Two lines in `metrics-lessons.spec` still describe what round 015 changed
Where: `metrics-lessons.spec`:
- line 86, the case title "dates a YYYY-MM-DD day as days since 1970-01-01 (UTC)". The Design no longer says UTC: `day` is zone-free arithmetic, and the cutoff is local.
- line 117, the comment "created long before lessons existed": R0030 is now created 2030-05-31, the day before the cutoff.
Evidence: the diff 9fed9c6..84dd223 changed the dates but neither line.
Lesson: ticket-prep/restated-rules-move-together
Recommendation: drop "(UTC)" from the title. The Test plan cites cases by "…" prefix, so check that no Rules row quotes the old title. Change the comment to "created the day before lessons, while its commits are all from 2020 to today". Make both edits in the same change as F1.

Verdict: changes
