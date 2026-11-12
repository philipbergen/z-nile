# c0263 hand-off to c0280: ./zn who: derive the author, status changes, the merge and the worker from git and the spend rows

Specs here: who.spec.luau.txt (all cases but the board one, which is c0284's), provenance-cases.spec.luau.txt (all the specs here are `.luau.txt` so the gate does not run an excerpt; copy one back to `.luau` to use it) (trailers and commits, derive and merge, trail log). Back-fill by deriving: old done and backlog items need no write.

Everything below is the c0263 prep text (design-review rounds 003-007), moved here when the user split the issue ("Split it and prototype first, like c0265"). It was NOT prototyped except where it says so; the core layer (c0263: provenance.md, ./zn record, the append-only publish rule, audit, the union of two writers) is prototyped on branch proto-c0263-raft, and this issue prototypes on top of it. Spec files beside this one are the sequestered specs of that prep: they were written against the unprototyped design, so run them on your prototype and fix the ones that cannot pass for a correct implementation.

## The derivation table (rows idea, status changes, unblocked, rafted, delivered, merged, worker)

| event | derived from git | stored in the record | written by |
|---|---|---|---|
| idea | the author of the capture commit (`human:<name> (from git)`); when no commit names the ticket (a renumbered item) the author of its first add, marked `(from git, first add)` | nothing | nothing |
| status changes | the author and trailer of each `tracker: <id> <status>` commit of the item's life | nothing | nothing |
| `approved` | nothing (a bot may push it) | the human, the design hash, the user's words | `./zn approve` |
| `unblocked` | the author of each `tracker: <id> new` commit of the life that did not also append a stored row (per commit, not per event), printed as `unblocked` and never also as a status line | the actor | `status <id> new`; c0250's resolve through the record API |
| `confirmed` (c0260), `ranked` | nothing | the actor | `./zn record`, called by their tickets |
| `rafted` | (no stored row) the oldest life commit at which the document's `raft:` became the current value and stayed so to now: a ready, a restamp or the move to `done/` keeps the value and starts nothing, an unfold breaks the run. The edge gives `select` the value after each life commit (`raftAt`, one `git show` per commit that touches the document, `who` only) | the actor, `raft=<R-id>`, one row per ticket | `new raft`, `fold`, `recombine`, an emergent `new issue --raft` |
| `delivered` | (no stored row) the life commit that first added the ticket's document under `done/` | the actor, `raft=<R-id>`, one row per member | `done` |
| merged | always: the author of that same `done/` commit (trailers ignored: a squash is authored by the user with the agent as co-author), as a `merged` entry of its own (the account that merged the raft PR) | nothing | nothing |
| worker (host, CLI, model) | read at `who` time from the ticket's spend rows: the newest `deliver` row that has a model, else the newest `build` row that has one | nothing | c0254 puts host and CLI on the rows; until then only the model column exists |

## Actor grammar for values read from git (the stored form without suffix is c0263's)

**Actor grammar** (the user's, 2026-11-07), the stored form: `human:<name>`, or `agent:<model> effort <level>`; a value read from git ends ` (from git)` (` (from git, first add)` for an idea taken from a first add); `unknown` when nothing says. `<model>` is `provenance.modelId(text)`: lower-case, each run of non-alphanumeric characters one `-`, trimmed, so `.models.toml`'s `grok-4.7` and git's `Grok 4.7` are both `grok-4-7` and `Claude Opus 5.5` and `claude-opus-5-5` the same; the version is part of the model id; `<level>` is the spec's `effort` or `unknown`.

## Behaviour 1 (author) and 7 (who)

1. **Author (AC3, AC8).** `./zn who` reads the item's life with `trail.read` (the reader `./zn capture` uses: the last time the document went from absent to present, cut at a compaction, so a reused number is a new life) and takes the capture commit by `trail.capture`: its author, `human:<name> (from git)`. Nothing is stored. A trailer is never read for the idea.

## Behaviour 7

7. **`./zn who <id>` (AC3, AC8).** Prints one line per event, oldest first: `<when>  <event>  <actor>  <detail>  (git | record)`, parts joined by two spaces, an empty detail omitted: the derived entries (idea; each status change, as an event named `status:<status>` (`status:preparing`, `status:prepared`) with the author of its `tracker: <id> <status>` commit in the item's life, its trailer's agent when it has one, except that a `tracker: <id> new` commit is printed once, as `unblocked`; the git fallbacks of the table for an event with no stored row; and always a `merged` entry for the commit that added the item under `done/`, so the delivering agent and whoever merged are both on the record) and the stored rows, the worker from the spend rows appended to a `delivered` line as `worker=<…>`. A commit's actor is `agent:<modelId> effort unknown (from git)` when it carries a `Co-Authored-By`/`Co-authored-by` trailer whose email is not the email of any commit author in the log (a person is whoever commits), else `human:<author> (from git)`; the engine's own `tracker: <id> <status>` publishes carry no trailer, so a give-back an agent ran reads as the human git shows (Q5, stated). Ties in time keep derived before stored, then file order. Read-only, so it may run in the main checkout. Existing done and backlog items work with no write.

## Interfaces (pure: fromTrailer, fromCommit, select, merge, workerOf; trail.Commit author/email/trailers and the new log format)

`z-nile/engine/provenance.luau` (new; pure; requires no module that touches the file system; strict):
```
type Hint = { agent: boolean, effort: string? }
type Row = { when: string, event: string, actor: string, detail: string }
type Commit = trail.Commit                                          -- with author, email, trailers
type Entry = { when: string, event: string, actor: string, detail: string, source: "git" | "record" }
type Derived = { idea: Entry?, statuses: { Entry }, unblocked: { Entry }, rafted: Entry?, delivered: Entry?, merged: Entry? }
provenance.EVENTS: { "approved", "unblocked", "confirmed", "ranked", "rafted", "delivered" }
provenance.PUBLISHED: { "unblocked", "confirmed", "ranked" }      -- what ./zn record may publish
provenance.modelId(text: string): string
provenance.human(name: string): string
provenance.agent(model: string, effort: string?): string        -- "agent:<modelId> effort <effort|unknown>"
provenance.isValid(value: string): boolean                       -- the stored grammar, with the optional " (from git)"
provenance.isLive(value: string): boolean                        -- human:<name> or agent:<model> effort <level>, no suffix
provenance.resolve(flag: string?, env: string?, hint: Hint, gitName: string?): (string?, string?)
provenance.fromTrailer(trailer: string): string?
provenance.fromCommit(author: string, trailers: { string }, people: { [string]: boolean }): string   -- people: every commit author's email in the log, from the same pass
provenance.parse(text: string): ({ Row }?, string?)              -- provenance.md; refuses a bad row
provenance.render(id: string, rows: { Row }): string
provenance.record(text: string?, id: string, event: string, actor: string, detail: string, now: string): (string?, string?)
provenance.appendOnly(old: string?, new: string, id: string): string?     -- the publish and gate rule: every cell of every old row (when, event, actor, detail) unchanged, in place
provenance.union(base: string?, ours: string, theirs: string): string    -- Behaviour 11's merge, pure: the base's rows positionally, then theirs' new rows, then ours' new rows minus theirs' taken as a multiset (a repeated row stays repeated)
provenance.exemptParse(text: string?): ({ [string]: string }?, string?)   -- nil text: no list on the base, the rule is not in force
provenance.exemptRender(entries: { [string]: string }): string
provenance.approvalProblem(id: string, hash: string, rows: { Row }, exempt: { [string]: string }?): string?   -- the doors' one rule
provenance.approval(rows: { Row }, hash: string): ("none" | "stale" | "current", string?)
provenance.select(life: { Commit }, id: string, state: string, raft: string, people: { [string]: boolean }, raftAt: { [string]: string }): Derived   -- raftAt: the document's raft: after each life commit that touches it
provenance.merge(derived: Derived, rows: { Row }, worker: string?): { Entry }
provenance.workerOf(row: { model: string?, host: string?, cli: string? }?): string?   -- the spend row chosen as in the table
provenance.problems(path: string, text: string): { string }      -- audit
```
`trail.luau` gains `author`, `email` and `trailers` on `trail.Commit` (optional fields, additive) and `isDoc` stops counting `provenance.md` as a document (it would otherwise break the life rule). Its log format becomes `--format=@@%H %ct %s%n@A%an%n@E%ae%n@T%(trailers:key=Co-Authored-By,valueonly,separator=%x1f)` with `--name-status`: one header line, then three tagged lines (`@A` author, `@E` email, `@T` the trailer values separated by the unit separator, empty when none); a change line `M\tpath` and these tags cannot be confused, and no commit body is read, so a body line that looks like a change line cannot misparse (a trail case pins it; `capture`'s output is unchanged). Callers: `main.luau` (`cmd.approve`, `cmd.who`, `cmd.record`, the appends in `status`, `new raft`/`fold`/`recombine`/emergent, `done`, the refusals in the carried move, `fold`, `new raft` and `ready`, the shared union merge), `publish.luau`, `dispatcher.luau` (the rafting gate, `ZN_ACTOR`/`ZN_VIA` per attempt and script step), `dispatch.luau` (the prep gate), `board.luau`, `audit.luau`. `models.luau` is read only.

## Where it bites, trail

### Where the new file and refusal bite (each place read, not assumed)

## Edge cases and experiments: E1-E5, E9, E11 (kept in c0263.md history; see below)

- **E1** Does git carry the capture commit's author for a `tracker: new` item? Method: `./zn capture c0117`. Result (run): pass, `fb7fd805 Philip Bergen "tracker: new c0114 c0115 c0116 c0117 c0118 …"`.
- **E2** Can one `git log` pass give every derived entry's source, fast? Method: `git log origin/main --reverse -U0 --no-renames --format=… -- <roots>`. Result (run): pass, 0.6 s, 1,900 commits. `who` reads one item's trail (`trail.read`), the board one pass; the item's life, the compaction cut and a reused number are trail's rules (design review 003 F12), not subject matching: 14 `tracker: <id> new|preparing|prepared` commits predate the 2026-10-05 compaction and name ids that now belong to other items.
- **E3** Does `git var GIT_AUTHOR_IDENT` honour `GIT_AUTHOR_NAME` and the config? Result (run): pass: with the env `e2x <a@b>`-style names it prints them, without it `Philip Bergen <philip.bergen@me.com>`; with no identity it fails (`empty ident name`): the human is then `unknown`.
- **E4** Who is a person in trailers? Result (run): trailers read `Claude Opus 5.5` (620), `Claude Sonnet 5.5` (102), `Cursor`, `Grok 4.7`, `Kimi Code` and two `Philip Bergen <philip.bergen@me.com>` on commits authored `Phil`: the same person under two names, so the rule is the trailer's email against the emails of every commit author in the log. The R0052 squash (`e8c832ff`, author `Phil`) carries `Co-Authored-By: Claude Sonnet 5.5`.
- **E5** Which variables say an agent session runs a command? Result (run by a reviewer in a Claude Code session): `CLAUDECODE=1`, `CLAUDE_EFFORT=high`, `AI_AGENT=…`; the model id is not among them. The environment reaches Lune's exec children (a probe printed `CC=1`), so specs that assert the human fallback or run `approve` clear all three and `ZN_DISPATCH`.

## E9, E11

- **E9** (run) How long does the board's history read take? Method: a probe calling `trail.parse` once per item folder (336 items) on the 19,823-line log (review 004 F9): 5.2 s; once with every folder in `dirs`: the parse is O(lines) (0.13 s for the `git log`, the parse in the same order). Design: the single call of Behaviour 8; fallback if the board is still slow: the board shows the stored rows only and `who` derives on demand.
- **E11** (run) Does the `raft:`-value rule pick the rafter on real done items? Method: a probe over 8 done z-nile issues, taking each life's commits with `git log --no-renames --name-status` over the item's three folders and `git show <sha>:<path>` for the `raft:` value after each. Result: it picks the rafting PR's or the prep PR's squash (`tracker: raft R0063 Local ci only (#179)`, `tracker: prep R0079-R0080 rafts … (#226)`, `raft reuse test results (#232)`), never the readier or the merger; for five items whose raft was set before the tracker moved into z-nile it picks the move commit (`R0043: z-nile 2, the tracker moves into z-nile`), because the probe looked at z-nile's folders only: `trail.dirs` over every root that ever held items covers the earlier history, so the real reader sees the earlier commit. The earlier subject-only rules covered 22 (a fixed shape) or 66 (any subject naming the raft) of 85 rafts and picked the readier or the merger on real items (review 006 F2).

## Rules and mutants rows (who, rafter, life, trailers)

| the stored grammar accepts the forms and the suffixes, refuses the rest (`none` included); one spelling per model | provenance :: grammar and resolution | `isValid` accepts any string after `agent:`; dots kept so `grok-4.7` and `grok-4-7` both live | run |
| flag beats env beats agent session beats git name; a bad given value refuses; no identity is `unknown`; a live input is only the recorded forms | provenance :: grammar and resolution; record :: status new | env wins over the flag; the session hint ignored so an agent is recorded as the user; `--actor none` accepted | run |
| a trailer whose email is a commit author's is a person, else an agent with a normalised model id | provenance :: trailers and commits | a human co-author read as an agent; `claude-opus-5.5` | run |
| `provenance.md` rows are unnumbered, in a closed event list and the stored grammar; a `\|` or newline cannot split a row; the parser refuses an unknown event and every malformed row; union keeps both sides' rows once | provenance :: the record | a free event name; a pipe splits a row; a parser that skips bad rows; the union drops a side or doubles a shared row | run |

## rows

| `who` merges derived and stored oldest first, a stored row winning over a git fallback of its event, `unblocked` hidden per commit, a first-add idea marked, `merged` the commit author, old items needing no write | who :: (all cases); provenance :: derive and merge | the first rafting commit used; the done commit counted as a rafter; the record repeated by a fallback; one duplicate `unblocked` per give-back; the agent trailer on `merged` | run (pure) / reasoned (command) |

## rows

| the derived rafter is whoever made `raft:` the current value and it stayed so | provenance :: derive and merge; who :: the rafter of an old item | the newest or the oldest commit naming the raft; the readier or the merger | run (pure) / reasoned (edge) |
| `who` reads only the item's current life (a reused number, a compaction) | who :: a reused number | a commit of a reused number is the item's | reasoned (trail not prototyped) |

## Acceptance AC2, AC3, AC8

- AC2: a `Co-Authored-By` trailer becomes a normalised agent actor; a commit's actor is an agent only for a trailer whose email is not a commit author's, otherwise the author, both `(from git)`.
- AC3: `./zn who <id>` prints the idea's author from the capture commit and each status change's author (and agent trailer) from git, for the item's current life only (a reused number or a compaction does not leak in), works for an old item with no record and in the main checkout, and writes nothing.

## AC8

- AC8: `provenance.merge` orders the derived and stored entries oldest first (by the commits' dates; a derived entry before a stored one in the same minute), lets a stored row win over a git fallback of its event, appends the worker read from spend rows, and `provenance.select` takes the oldest commit at which `raft:` became the current value and stayed so (not a ready, a restamp or the move to `done/`; none when `raft:` is empty), prints a `tracker: <id> new` commit as `unblocked` only, and gives a `merged` entry for the `done/` commit.

## Note from c0263 review 008
c0263 lands `provenance.parse` as an exact grammar (no skipped lines): the derivations read rows only through it.
