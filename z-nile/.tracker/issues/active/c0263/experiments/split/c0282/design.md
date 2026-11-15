# c0263 hand-off to c0282: lifecycle rows: unblocked on status new, rafted on new raft/fold/recombine/emergent, delivered on done

Specs here: lifecycle.spec.luau.txt, record.spec.luau.txt (the status-new case, the raft's give-back, fold and recombine; the ./zn record, conflict, folder-move and audit cases stay in c0263), dispatch.spec.luau.txt (the ZN_ACTOR per attempt and the script step cases, the rafting gate; the prep-gate case is c0283's). The union merge and the folder-move fix are in c0263 (mergeRef in main.luau, merge.directoryRenames=true): c0282's `new raft` adds a record in a worktree, which is the c0084/spend-command shape; run c0084/spend-command on the prototype.

Everything below is the c0263 prep text (design-review rounds 003-007), moved here when the user split the issue ("Split it and prototype first, like c0265"). It was NOT prototyped except where it says so; the core layer (c0263: provenance.md, ./zn record, the append-only publish rule, audit, the union of two writers) is prototyped on branch proto-c0263-raft, and this issue prototypes on top of it. Spec files beside this one are the sequestered specs of that prep: they were written against the unprototyped design, so run them on your prototype and fix the ones that cannot pass for a correct implementation.

## Behaviours 3, 4, 5 (unblocked, rafted, delivered)

3. **Unblocked by (AC6).** `cmd.status` appends `unblocked | <live actor> | ` to the issue's `provenance.md` in the same published commit as the status line, on every `status <id> new` (a raft's move: each issue it changes, never the raft). `release`'s give-back is not recorded. c0250's resolve calls `./zn record <id> unblocked --detail "block=<reason>"` once per resolution ("each time"), on the ticket or on the blocked raft: rows accumulate, `who` prints all.
4. **Rafted by (AC6).** At each place the engine writes `raft:` to a non-empty value (`new raft` in its published and offline paths, `fold`, `recombine`, an emergent `new issue --raft`) it appends `rafted | <live actor> | raft=<R-id>` to that ticket's `provenance.md`, one row per ticket (a layer per ticket, even when a raft holds several); the row rides the rafting PR with the `raft:` line, so the rafting PR merge is when it lands. `unfold` removes nothing; `who` shows the newest `rafted` row whose `raft=` is the ticket's current `raft:`, earlier ones as history.
5. **Delivered by (AC6).** `done` appends `delivered | <live actor> | raft=<R-id>` to each member's `provenance.md` and stages it with the moves, so `done`'s rollback (`git reset --hard`) removes it and a retry appends once; one row per member, riding the raft PR. Under zz-rules' Merging the agent that ran `done` merges its own PR, and the squash commit's `Co-Authored-By` agrees. The row is made before the merge, so where the user merges the run PR it still names the delivering agent: a limit, stated. The worker (host, CLI, model) is not stored: `who` reads it from the ticket's spend rows (Q4): the model column the dispatcher already writes today, and the host and CLI columns once c0254 adds them (the dispatcher starts passing them with c0254); with none, the row has the actor only.

## Behaviour 10, the rafting gate part

10. **Where the writes may land (AC6, AC10).** The publish validator accepts an issue's or raft's `provenance.md` as a create or an append only (every old row byte for byte, at least one new), like `spend.md`, and only when every new row's event is one `./zn record` may publish (`unblocked`, `confirmed`, `ranked`): an `approved`, `rafted` or `delivered` row is written in a PR, never published (a status-new append built from a worktree's file would otherwise leak a PR's row onto `main`); in `active/` only `unblocked` rows; `publish.allowed` learns the name. The dispatcher's rafting gate accepts, beside the `raft:` line, `<issue folder>/provenance.md` whose old rows are unchanged and whose new rows are `rafted` rows only (the file may already hold the prep PR's `approved` row). `audit` reports a `provenance.md` that does not parse, has an unknown event, a bad actor, or a header naming another id.

## The live actor (ZN_ACTOR, ZN_VIA per attempt and script step)

**The live actor** (a command that records), in this order: `--actor "<value>"`, else `ZN_ACTOR` (only `human:<name>` or `agent:<model> effort <level>`, nothing else, refusing the command before it changes anything; the dispatcher sets `ZN_ACTOR` for each attempt of a model step from that attempt's spec, `provenance.agent(spec.model, spec.effort)`, and for a script step it runs itself (`raft-plan --apply`, `z-ready`) the user who started the pipeline, `human:<git name>`, with `ZN_VIA=dispatch:<step>`, which a row records as `via=dispatch:<step>`); else, when `CLAUDECODE` or `AI_AGENT` is set and non-empty, `agent:unknown effort <CLAUDE_EFFORT|unknown>`; else `human:<name from git var GIT_AUTHOR_IDENT>`, or `unknown` when git has no identity.

## Table rows unblocked, rafted, delivered

| `unblocked` | the author of each `tracker: <id> new` commit of the life that did not also append a stored row (per commit, not per event), printed as `unblocked` and never also as a status line | the actor | `status <id> new`; c0250's resolve through the record API |
| `confirmed` (c0260), `ranked` | nothing | the actor | `./zn record`, called by their tickets |
| `rafted` | (no stored row) the oldest life commit at which the document's `raft:` became the current value and stayed so to now: a ready, a restamp or the move to `done/` keeps the value and starts nothing, an unfold breaks the run. The edge gives `select` the value after each life commit (`raftAt`, one `git show` per commit that touches the document, `who` only) | the actor, `raft=<R-id>`, one row per ticket | `new raft`, `fold`, `recombine`, an emergent `new issue --raft` |
| `delivered` | (no stored row) the life commit that first added the ticket's document under `done/` | the actor, `raft=<R-id>`, one row per member | `done` |

## Overrides touching this layer (c0053/commands-prep "a published move abandons prep for a raft": the published commit also holds the members' provenance.md)

- `c0053/commands-prep.spec` :: "a published move abandons prep for a raft and its members in one commit" (lines ~44-77): the published commit now also holds the members' `provenance.md`, so it expects the count of files it names (3, not 2).

## Rules and mutants rows

| `status new` appends `unblocked` in its published commit, per issue, never to a raft; `release` appends nothing | record :: status new; a raft's give-back | only `status:` is written; the raft gets a record; `release` stamps | run |
| `new raft`, `fold`, `recombine`, an emergent issue append `rafted` per ticket (with `via=` only under `ZN_VIA`); `unfold` keeps history | record :: a raft's give-back, fold and recombine; lifecycle :: offline new raft, emergent | `fold` writes `raft:` only; `unfold` deletes the row; `via=` always written | run |
| `done` appends `delivered` on every member and stages it with the moves; no worker is stored | lifecycle :: an emergent issue ... done | only the first member; the row left unstaged by a rollback; the worker stored | run |

## rows

| the rafting gate accepts an append (after the prep's `approved` row, after main's rows) and refuses a `delivered` row, an `approved` row, an edited old row and a second file | dispatch :: the rafting gate | the gate only accepts a new file; a delivered row passes | reasoned (dispatcher not prototyped) |

## rows

| a failed `done` leaves no delivered row and a retry appends exactly one | lifecycle :: an emergent issue ... done | the row left unstaged | run |

## rows

| each attempt of a step has its own `ZN_ACTOR`; a script step records the user and `via=dispatch:<step>` | dispatch :: each attempt's ZN_ACTOR; a script step | the first attempt's value kept for the fallthrough; the dotted model unnormalised; a script step records no `via` | reasoned |

## Acceptance AC6 (the lifecycle part), AC7 (the per-attempt ZN_ACTOR)

- AC6: `status <id> new` appends an `unblocked` row in its published commit (each issue of a raft's move, never the raft; `release` none), `new raft`, `fold`, `recombine` and an emergent `new issue --raft` append a `rafted` row per ticket (`unfold` keeps the history; a script step records `via=dispatch:<step>`), `done` appends a `delivered` row per member staged with the moves, `./zn record` publishes the events c0250, c0260 and the rank ticket will call and refuses any other, the engine's merge of `origin/main` unions a conflict confined to `provenance.md` and aborts on any other, and the publish validator (through `publish.commit`) and the dispatcher's rafting gate (with a record that already holds a prep `approved` row) let a record through only as appended rows of the allowed events.
- AC7: the dispatcher never merges a prep PR, whatever `auto_merge` says (also with `prep` absent), stopping with exit 4, the existing reason and the `./zn approve` suffix; a dispatched worker's `approve` is refused; and each attempt of a step has `ZN_ACTOR` from its own spec.

## Note from c0263 review 008
c0263 lands `provenance.hint(env)` (an agent session includes a dispatched step, `ZN_DISPATCH`) and `liveActor`: the dispatcher's `ZN_ACTOR` per attempt wins over the hint. `mergeRef` unites the record in every `git merge` of origin/main; `union` refuses a side that edited an old row, so a branch that appends a rafted row is fine. `done` promotes the folder with its record: c0263 refuses publishing into `done/`.
