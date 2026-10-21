# Review 017: R0042 (design mode)
Inputs: prep-z-nile at 7a4505a: R0042.md, check.sh, harvest.md; design-review-016 and design-refute-016; 006 to 015 skimmed; c0111's and c0119's documents, check.sh files and acceptance specs; the diff 84dd223..7a4505a. The prototype `.worktree/proto-scope-fidelity`: both issue folders are identical to this tree (`diff -r`). I read its metrics reader (`main.luau`: the cutoff is `os.date("%Y-%m-%d", added)`, and `created:` is written with `os.date("%Y-%m-%d")`, so both use the process's zone) and `trackerfix.tr` (its `env` argument reaches `fixture.exec`).
Round 016's F1, F2 and F3 are answered as recommended, and I don't reopen them or the user's decisions (read-only `capture`, Luau on Lune, "Never cross; mark it", the `Scope decision` and `Decided with the user` lines).

Run on the prototype:
- c0111's and c0119's acceptance specs: `65 passed, 0 failed, 11 spec files`.
- `metrics-lessons.spec` with the host TZ unset, Pacific/Auckland, Pacific/Kiritimati and Pacific/Pago_Pago: `5 passed, 0 failed` each.
- `luau-lsp analyze` of `scripts/tracker` and both acceptance folders: exit 0.
- `tracker.sh metrics`: `before | 41 | 176 | 4.3`, `after | 0 | 0 | 0.0`.
- `capture c0111` (`ef5a7a5`) and `capture c0119` (`ab750c0`): both unmarked.

I didn't run `promote-check`.

Reasoned from the fixture: the new state-folder row holds. Skipping `done/` drops R0020 (after, 1 round), so `after | 2 | 3` becomes `after | 1 | 2`. Skipping `active/` drops R0030 (before, 2 rounds), so `before | 1 | 2` becomes `before | 0 | 0`. Both fail the case.

Lessons pass (item 10, `lessons --when design --full`):
- `pin-call-site-arguments`: passed. The zone is pinned by `TZ`, and the commit instant falls on different UTC and local days, so the UTC mutant fails.
- `seed-every-enumerated-case`: passed. There is one raft each in the backlog, `active/` and `done/`.
- `restated-rules-move-together`: passed. The Metrics reader, the Rules row, AC9, the Test plan, E10 and the spec comments agree. No document still describes the cutoff as UTC.
- `spec-design-correspondence`, `one-reader-per-format`, `no-vacuous-pass`, `item-history-spans-moves-and-compaction`, `new-rules-migrate-existing-work`, `exhaustive-lists-name-new-things`: unchanged since round 016, still passed.
- `never-narrow-captured-scope` and `no-scope-cut-as-fix`: see below. This review recommends nothing.

Scope fidelity (item 11, against the prototype's `capture`):
- c0111: compared with the capture, the text before `## Design` differs in three ways:
  - the four `Scope decision` lines;
  - the Non-goals: the captured items moved to c0112 or into the Design, by those decisions;
  - the `As designed` paragraph.

  The captured Solution is verbatim, and every outcome, including metrics (AC9), has a Design and a criterion.
- c0119: the only difference is the `Decided with the user (2026-10-20)` block.

No findings.

Verdict: approve
