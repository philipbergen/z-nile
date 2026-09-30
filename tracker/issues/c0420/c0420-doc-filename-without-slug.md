---
id: c0420
type: chore
title: Doc filename without slug
raft: R0020
depends_on: []
emergent: false
design: reviewed
created: 2026-09-30
---

# c0420: Doc filename without slug

## Problem
Every tracker item's document is named `<ID>-<slug>.md` (`c0420/c0420-doc-filename-without-slug.md`), and the slug is read back from the filename. That makes id collisions **silent**:
- Two branches that each create the next free id (both `c0420`, from captures or preps running in separate worktrees) add *different paths* (`c0420-foo.md` and `c0420-bar.md`), plus a byte-identical template `check.sh` (the template only fills in the id). Git sees no conflict.
- Squash-merging both exits 0 and leaves one directory holding two documents. The tracker returns whichever its directory listing yields first, so the other item vanishes from `list`, `members` and `prompt`, and GitHub still shows the PR as mergeable with green CI. (Reproduced in a scratch repo, c0041's E7.)

The worktree rule (c0041) makes this likelier, because captures and preps used to be serial on `main` and now run side by side.

## Non-goals
- **Changing ids, id allocation or the numbering scheme.** Ids stay `f`/`d`/`c` + four digits and `R` + four digits, and the next free number is still the next multiple of 10.
- **Preventing the collision itself.** Two branches can still pick the same number; this issue makes that a loud git conflict on `<ID>.md` instead of a silent merge, and the tracker skill says how to resolve it (`renumber` before merging). Warning about a shared number across prefixes (`f0420` and `c0420`) is c0041's landing step.
- **Renaming other files** (`check.sh`, `spend.md`, reviews) or item directories.
- **Validating slugs found in legacy filenames.** `migrate` copies whatever the old filename held.
- **Supporting other rafts that are in flight during the transition.** The policy (user decision, 2026-09-30) is that R0020 is executed and merged while **no other raft is started or active**, and no raft starts until it has merged. Captures and preps that only add or edit backlog documents adopt the layout by merging `main` and running `migrate` (a spec case pins that); a branch whose items were *moved* (a started raft) cannot, because a move and a rename of the same document conflict in git (rename/rename), which this chore doesn't try to resolve.

## Solution
- The document is `<ID>/<ID>.md`. The slug moves into the frontmatter (`slug: doc-filename-without-slug`), next to `title`.
- `store` reads the slug from the frontmatter. A document with no `slug:` is an error naming the file, and a directory that still holds only a legacy `<ID>-<slug>.md` is an error that points at the migration command.
- **`tracker.sh migrate`** converts legacy documents in place (`git mv`, so history follows), in every state directory, for issues and rafts, and is idempotent. The repo itself is migrated as part of this issue, and the same command brings any in-flight branch up to date after it merges `main`.
- `new` writes the new layout and validates the slug. `renumber` renames `<old>.md` to `<new>.md`.
- The three specs that assert the old paths are updated to the new ones.

## Design

### Layout
`tracker/{issues,rafts}/[active/|done/]<ID>/<ID>.md` (+ `check.sh`, `spend.md`, reviews, `acceptance/`). Frontmatter gains `slug:` (kebab-case, `^[a-z][a-z0-9-]*$` for new items), placed after `title:` in the templates:
```
---
id: c0420
type: chore
title: Doc filename without slug
slug: doc-filename-without-slug
raft: R0020
...
```

### `scripts/tracker/store.luau`
- **`docIn(dir, id)`** returns `{dir}/{id}.md` when it exists. Otherwise, if the directory holds a legacy `{id}-*.md`, it raises `{dir}: {file} uses the legacy document name; run scripts/tracker.sh migrate`. Otherwise it raises `{dir} has no {id}.md`. A directory that holds both `{id}.md` and a legacy file uses `{id}.md` (migrate reports that case).
- **`store.find`** builds `Item.slug` from `store.readFront(doc).slug`. A missing or empty `slug` raises `{doc} has no slug: in its frontmatter; run scripts/tracker.sh migrate`. `Item.doc` is `{dir}/{id}.md`.
- The layout comment and the `Item.doc` comment are updated.

### `scripts/tracker/main.luau`
- **`new issue` / `new raft`**: the slug must match `^[a-z][a-z0-9-]*$` (else `invalid slug`, nothing created). The template variable `SLUG` is passed, and the document is written to and printed as `{dir}/{id}.md`. Everything else (ids, `--raft`, `--single`, `check.sh`) is unchanged.
- **`renumber`**: the document move is `{dest}/{old}.md` to `{dest}/{new}.md`. The rest (id and reference rewriting across the tracker) is unchanged.
- **`cmd.migrate`** (`migrate`, no arguments): for every directory `tracker/{issues,rafts}/[active/|done/]<ID>/` whose name is an item id, scanned directly (never through `store.find`, which rejects legacy names):
  1. if `<ID>.md` exists and no legacy `<ID>-*.md` does, skip it;
  2. if both exist, or two legacy files exist, report `{dir}: ambiguous documents: {files}`, leave the directory alone, and remember to exit 1 at the end;
  3. otherwise rename the single legacy file to `<ID>.md` with `git mv` (plain `fs.move` when the file isn't tracked), and set `slug: <slug>` in its frontmatter with `store.setFront` (appended if absent; left alone if the frontmatter already has a `slug:`).
  Print one line per converted document, `{old} -> {new}`. Exit 0 when nothing was ambiguous, else 1. Running it twice changes nothing.
- **USAGE** gains `migrate`. `start`'s branch name (`{raft.id}-{raft.slug}`) and `prompt`'s placeholder raft read the slug from the frontmatter through `Item.slug`, so they behave as before.

### Templates
`tracker/templates/issue/doc.md` and `tracker/templates/raft/doc.md` gain `slug: {{SLUG}}` after the `title:` line.

### Migrating the repo
After the tooling works, run `scripts/tracker.sh migrate` and commit the result: every existing document (about 50, in all states, including this raft's three and the prepped ones) becomes `<ID>.md` with a `slug:` line. Nothing else in the tracker tree changes.

### Promoted and ordinary specs that assert the old paths
Three specs name the old document paths; this chore is the test fix the testing skill calls for ("a wrong promoted spec is a chore"), and the change is limited to path strings and fixture file names:
- `tests/acceptance/c0010/tracker-lifecycle.spec.luau`: the expected paths printed by `new` and the files it reads (`f0010-alpha.md` becomes `f0010.md`, and so on).
- `tests/acceptance/c0410/rounds.spec.luau`: the fixture documents it writes (`R0010-a.md` becomes `R0010.md` with a `slug:` line, and so on).
- `tests/tooling/metrics-rounds.spec.luau`: the same fixture change.
Assertions, counts and expectations other than those paths are not touched (JC1).

### Docs
The ticket-prep skill's line "In `R…-slug.md`, before any issue gets detail" becomes "In the raft document (`R<NNNN>.md`), before any issue gets detail". The tracker skill's layout line becomes `<ID>/<ID>.md   the document (frontmatter incl. slug + sections from tracker/templates)`, and its "Conflicts" section says: a merge that reports `CONFLICT (add/add)` in `tracker/…/<ID>/<ID>.md` is two items that picked the same number. Run `git merge --abort`, `git fetch origin main`, then `scripts/tracker.sh renumber <ID> <next free>` on your own branch, where next free is the next multiple of 10 above the highest number of that kind in **both** your tree and `origin/main` (`git ls-tree -d --name-only origin/main tracker/issues/ tracker/issues/active/ tracker/issues/done/`, or `tracker/rafts/…` for a raft), then merge again. After merging a `main` that contains this change, a branch that still has legacy-named documents runs `scripts/tracker.sh migrate` and commits. Only a `CONFLICT (add/add)` on `tracker/…/<ID>/<ID>.md` means two items picked the same number. A content conflict on a document is two edits to one item: resolve it like any other merge and never renumber.

### Scalability
- `find` reads one more file (the frontmatter of the document it already opens). `list` and `all` already read every document for titles, so the cost is unchanged: about 100 small files.
- `migrate` is O(items), run once per repo and once per stale branch.

### Maintainability
- One rule for documents: the file is named by the id, the slug is data. Nothing parses a slug out of a filename any more.
- `migrate` is reusable for the next layout change and for in-flight branches.

### Usability
- **For developers**: a same-id collision now stops the merge with a conflict on the document, where it is visible, instead of losing an item. Paths are shorter and predictable (`tracker/issues/c0420/c0420.md`).
- **For agents**: `tracker.sh find <id>` is unchanged, and the old layout produces an error with the command that fixes it.

### Touched modules
- `scripts/tracker/store.luau`
- `scripts/tracker/main.luau`
- `tracker/templates/issue/doc.md`
- `tracker/templates/raft/doc.md`
- `tracker/issues`
- `tracker/rafts`
- `tests/acceptance/c0010`
- `tests/acceptance/c0410`
- `tests/tooling/metrics-rounds.spec.luau`
- `.claude/skills/tracker/SKILL.md`
- `.claude/skills/ticket-prep/SKILL.md`

### Affected specs
`lune run scripts/affected -- scripts/tracker/store.luau scripts/tracker/main.luau tracker/templates/issue/doc.md tracker/templates/raft/doc.md tests/acceptance/c0010 tests/acceptance/c0410 tests/tooling/metrics-rounds.spec.luau .claude/skills/tracker/SKILL.md` prints `ALL`, because `scripts/` forces a full run. New: `acceptance/naming.spec.luau`.

## Unknowns & experiments
- **E1 (run in prep: PASS)**: do two branches creating the same id merge silently today? Yes: in a scratch repo, branches that each add `tracker/issues/c0420/` with different document names and the same template `check.sh` squash-merge with exit 0, leaving one directory holding two documents (recorded in c0041's Verification log as E7).
- **E2**: does `git merge` report a conflict when both branches add `<ID>/<ID>.md` with different content? Git's add/add rule says so. The spec case `two branches creating the same id conflict on the document` pins it with the real `new`, and the prep prototype ran it (Verification log).
- **E3**: does `git mv` of a legacy document keep it a rename for `git log --follow`? The spec asserts the migrate run shows renames (`R`) in `git status --porcelain`.
- **E4 (prototype)**: the prep prototype (store, `new`, `renumber`, `migrate`, templates; reverted) passes the naming spec, the three updated specs and the full gate; planted mistakes are recorded in the Verification log.

## Regression guard
- **c0010's promoted `tracker-lifecycle.spec.luau`, c0410's `rounds.spec.luau` and `metrics-rounds.spec.luau`**: updated only in path strings (JC1) and must pass.
- **Every other tracker command** (`start`, `focus`, `commit`, `done`, `promote-check`, `prompt`, `metrics`, `members`, `check`) reads documents through `store`, so `tests/tooling/*` and the c0010 lifecycle spec exercise them on the new layout.
- **`spend`**: per-issue `spend.md` is unaffected.
- **Branches that still contain legacy documents** (captures and preps adding backlog documents) get a clear error and the `migrate` command, not silent misbehaviour; the case `a branch that added a legacy document merges a migrated main` pins the recovery. Started rafts are excluded by the transition policy (Non-goals).
- **Prepped rafts on the old layout.** R0060 (c0400) was prepped before this change; its design line and its three fixture specs were updated in place in the same PR (paths only), and the new permanent guard spec (`acceptance/guard.spec.luau`, promoted to `tests/acceptance/c0420/`) fails any later spec file that spells a literal `<ID>-<slug>.md` document path (names built by interpolation are out of its reach; only c0420's own `naming.spec.luau` is exempt, by full path).

## Test plan
`acceptance/naming.spec.luau` sets up a scratch `.cache/naming-e2e/` repo: a clone of the repo's committed HEAD with `main` forced as its branch and its `origin` removed (so the tracker's commands run freely), the working tree's `scripts/`, `tracker/templates/` and `.gitignore` overlaid, and the tracker emptied. Cases (`spec case → AC`):
- `new issue writes <ID>.md with a slug in the frontmatter` → AC1
- `new raft writes <ID>.md with a slug in the frontmatter` → AC1
- `new rejects a bad slug and creates nothing` → AC1
- `find, list, members and start work on the new layout` → AC2
- `a document without a slug is an error naming the file` → AC2
- `a legacy-named document is an error that points at migrate` → AC3
- `migrate converts legacy documents in every state` → AC4
- `migrate is idempotent and refuses an ambiguous directory` → AC4
- `a branch that added a legacy document merges a migrated main, then migrate converts it` → AC4 (a branch cut before the migration adds one legacy document and edits another; merging the migrated `main` exits 0, and `migrate` converts only the new document)
- `renumber renames the document and rewrites references` → AC5
- `two branches creating the same id conflict on the document` → AC8
- `guard.spec`: `no spec under tests/ or tracker/ names a <ID>-<slug>.md document` → AC10

`check.sh` adds repo-level checks for AC6, AC7 and AC9 (below).

### Rules and mutants
`run` rows were mutation-tested on the prep prototype (Verification log); `reasoned` rows were not run.

| rule | spec :: case | mutant it kills | checked |
|---|---|---|---|
| `new` writes `<ID>.md` with `slug:` | `new issue writes …`, `new raft writes …` | keep the `<ID>-<slug>.md` name; omit the `slug:` line | run |
| A bad slug is rejected before anything is created | `new rejects a bad slug …` | no validation; create first, validate later | run |
| The slug comes from the frontmatter | `find, list, members and start work …` | derive the slug from the filename; hard-code it | run |
| A missing slug is an error naming the document | `a document without a slug …` | return an empty slug | run |
| A legacy name is an error pointing at `migrate`, even when the document already has a slug | `a legacy-named document is an error …` | silently accept a legacy-named file; report "no such item" | run |
| `migrate` renames with history and adds the slug, in every state, issues and rafts | `migrate converts legacy documents in every state` | skip a state directory; skip rafts; drop the slug; `fs.move` instead of `git mv` | run |
| `migrate` is idempotent and refuses ambiguity | `migrate is idempotent …` | overwrite `<ID>.md` when both exist | run |
| A branch that added a legacy document adopts the layout by merging `main` and running `migrate` | `a branch that added a legacy document merges …` | `migrate` skips the backlog state | run |
| No spec names a legacy document path | `guard.spec` | scan only `tests/`, or skip `tracker/` | reasoned (the guard itself is the check; a scan that skips a directory can't be proven without injecting a file) |
| `renumber` renames the new document name and rewrites references | `renumber renames …` | leave the old document name | run |
| A same-id collision conflicts in git | `two branches creating the same id conflict …` | write a slug-named file | run |
| The repo is migrated; specs updated; docs updated | AC6, AC7, AC9 checks, JC1 | leave one legacy document or one old path | reasoned (repo-level greps and a ruling, not a mutation) |

## Acceptance criteria

### Checked
- **AC1**: `new issue` and `new raft` write `<ID>/<ID>.md` with `slug:` in the frontmatter and print that path; a slug that isn't lowercase kebab-case is rejected before anything is created.
- **AC2**: `find`, `list`, `members` and `start` work on the new layout; the slug (and so the raft branch name) comes from the frontmatter; a document without a slug is an error naming the file.
- **AC3**: A directory holding only a legacy `<ID>-<slug>.md` is an error that names the file and says to run `scripts/tracker.sh migrate`.
- **AC4**: `migrate` converts legacy documents of issues and rafts in backlog, active and done as renames (history preserved), adds `slug:`, changes nothing else, is idempotent, and refuses an ambiguous directory (exit 1) without touching it.
- **AC5**: `renumber` renames `<old>.md` to `<new>.md`, rewrites the id and every reference, and keeps the slug.
- **AC6**: The repo has no legacy `<ID>-<slug>.md` document, every item directory has `<ID>.md` with a `slug:` line, and `scripts/tracker.sh list` succeeds.
- **AC7**: The three specs that named the old paths pass on the new layout.
- **AC8**: Two branches that each create the next free id with different slugs conflict on `<ID>/<ID>.md` when merged.
- **AC9**: The tracker skill describes the new layout and the conflict and migration procedure (only `add/add` means renumber), and no skill, template or script text still says `<ID>-<slug>.md` or `…-slug.md`.
- **AC10**: No spec under `tests/` or `tracker/` names a legacy `<ID>-<slug>.md` document path (the permanent guard; `naming.spec.luau` is exempt by name).

### Judged
- **JC1: the three specs changed only in their paths.**
  - **Pass**: in `tests/acceptance/c0010/tracker-lifecycle.spec.luau`, `tests/acceptance/c0410/rounds.spec.luau` and `tests/tooling/metrics-rounds.spec.luau`, a diff against `main` shows only path strings, fixture file names and the `slug:` line in fixture frontmatter; no assertion was removed, loosened or added, and no case was deleted.
  - **Fail**: any other change. Quote it.

### Observed
None.

## Implementation steps
1. `cmd.migrate` and its USAGE line, **alone**, written so it never calls `store.find` (it scans directories). Run its cases against the old store. `scripts/tracker.sh commit` this: the tracker still reads the legacy layout.
2. **One commit for the layout switch.** `tracker.sh commit` reads every document through the store (`activeRaft` → `store.all` → `store.find`), so the store and the documents must change together: edit `store.luau` (`docIn`, `find`, slug from the frontmatter), the two templates, `new` (slug validation, `SLUG`, `<ID>.md`) and `renumber`; run `scripts/tracker.sh migrate` (it works with either store); update the three specs' paths and fixture `slug:` lines, the tracker skill and the ticket-prep line. Run no other `tracker.sh` command until the tree is fully migrated, then `scripts/tracker.sh commit`.
3. `scripts/tracker.sh check c0420`, `scripts/check.sh --full`, `promote-check R0020`. Commit.

## Verification log

- **Prototype run (2026-09-30), reverted, never committed:** about 90 lines across `store.luau`, `main.luau` and the two templates, then `tracker.sh migrate` on this repo (52 documents) and the three specs' paths and fixture `slug:` lines updated.
  - All 10 naming-spec cases pass; `scripts/check.sh --full` passes (346 specs); `tracker.sh check c0420` passes 10/10 once the tracker skill text is updated (AC9).
  - Twelve planted mistakes each fail the case written for them: `new` keeping the slug-named file (also breaks the collision case), a template without the slug, no slug validation, a hard-coded slug, a missing slug not an error, a legacy file silently accepted, `migrate` skipping `done/`, skipping rafts, dropping the slug, using `fs.move` instead of `git mv`, overwriting when both documents exist, and `renumber` leaving the old document name.
  - The first run exposed a spec gap: "legacy file silently accepted" survived, because a legacy document without a slug still errors (naming the file and `migrate`). The spec now also refuses a legacy-named document that already carries a slug, and the mutant fails.
  - A USAGE line mentioning `<ID>-<slug>.md` would trip AC9's own grep, so the executor words it differently.

- **Prototype run 2 (2026-09-30, after design-review-004), reverted, never committed:** the prototype was rebuilt stacked with c0041 and c0430 and re-run.
  - All 11 naming cases pass (new: `a branch that added a legacy document merges a migrated main, then migrate converts it`), the new guard spec passes once the three old specs are updated, `scripts/check.sh --full` and `promote-check R0020` pass (346 specs), and `tracker.sh check c0420` passes 10 of 11 (AC9, the skill text, is the executor's).
  - A thirteenth planted mistake, `migrate` skipping the backlog state, fails the new case (and cascades into the state-dependent ones).
  - Fixture hardening: the e2e specs set `gc.auto=0` and `maintenance.auto=false` for every fixture git command. Before that, back-to-back runs of the three e2e specs intermittently failed with missing-object or failed-copy errors from `git clone`, which looked like a background `gc --auto` from the previous fixture racing the re-created one. After the change, nine consecutive runs of the three specs passed.
