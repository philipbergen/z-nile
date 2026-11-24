# d0434 follow-ups: design drafts for D1 and D2 (not a ticket)

Written 2026-11-24 on branch `d0434-follow`, design only: no engine code, nothing published. This file is a draft for
three new tickets that the lead captures (commands at the end). It sits in d0434's folder only because that is where
the incidents' context is; it is not part of d0434's contract (the approval hash covers the design sections, the
acceptance specs, `check.sh` and `guesses.md`, not this file).

**Why new tickets and not d0434's document.** Both defects are outcomes d0434's capture never asked for (an act that
says an old branch is ours; which engine a worktree runs), and z-design's rule is that scope is what was captured, so
they go through z-idea as their own tickets. d0434 itself is not in `done/` (its folder is in the backlog, `status:
new-...`, `design: draft`, its acceptance specs not promoted, although PR #756 merged its code): see Open to the human,
O4.

**The owner's ruling that shapes D2** (2026-11-24, in answer to the old-worktree incident, verbatim): "This is why I
want zn to be a go executable with its own lifecycle". So D2's fix is ticket C (zn is one installed program); ticket B
is the interim cover until C is in place, and the part of it that stays useful after C (the restack marker check).

| draft | type | title (for `./zn new`) | slices | size | risk |
|---|---|---|---|---|---|
| A | defect | Restack cannot be told an old branch is ours | A1 | ~580 | risky |
| B | defect | A worktree runs its own old zn | B1, B2 | ~490 | risky |
| C | feature | zn is one installed program with its own lifecycle | C1-C4 | ~1,450 | risky |

The order the owner asked for: slice 1 is B1 (the printed commands, the skill sentence, and the two changes they need
to be true), slice 2 is A1 (the person's act), slice 3 is B2 (the hand-over to main's engine). C follows and replaces
B's hand-over target with the installed program. A and B are defects and may share one raft (A1 then B1 then B2, or
B1 first: they touch different functions of `restackcmd.luau`); C is a feature and has its own raft.

---

## Facts read before designing (with where)

- `refs/zn/pushed/<layer>` is written by `layergit.notePushed` only after zn's own push succeeded (`start`, `finish`,
  `restack`). `restackplan.trusted(originSha, pushed)` is `pushed ~= "" and pushed == originSha`: an older value is
  as untrusted as none. The refusal is in `restackcmd.walkBody` (line 273 at 5e8f5eaa4).
- Refs under `refs/zn/` are shared by every worktree (only `HEAD`, `refs/bisect`, `refs/worktree` and
  `refs/rewritten` are per worktree). The main checkout lists `refs/zn/pushed/R0070/1`, `/2` and `R0100/1` to `/5`
  today: the owner's hand-typed refs.
- The restack marker is `<this worktree's git dir>/zn-restack.state` (`restackcmd.stateFile`, `git rev-parse
  --absolute-git-dir`). `restackplan.parseState` ignores unknown keys, so a new line is readable by every engine that
  has the marker.
- The launcher `zn` resolves its engine from its own folder: `top="$(cd "$(dirname "$0")" && pwd -P)"`, then
  `cd "$top"` and `exec lune run z-nile/engine/main`. A worktree's `./zn` therefore runs that worktree's engine, as old
  as its branch. The one exception is `work`: when the caller's folder is another worktree of the same repository,
  `work` runs the invoked launcher's engine with the caller's worktree as its folder.
- `mainRoot()` in `main.luau` is the first entry of `git worktree list --porcelain` (the main checkout, also from a
  linked worktree); `workread.mainCheckout()` is the same. Neither depends on the machine: they are computed where the
  command runs.
- The person-in-a-terminal check for recording an approval has three layers: the launcher refuses the recording forms
  under `ZN_DISPATCH`, under `ZN_APPROVE_SESSION`, and when stdin is not a terminal (`[[ ! -t 0 ]]`); the engine
  (`main.luau` approve, `approvewalk.refuseAgent`) refuses under the same two variables, under any agent marker of
  `agentenv.MARKERS` (`CLAUDECODE`, `AI_AGENT`, `CLAUDE_CODE_SESSION_ID`, `CURSOR_AGENT`, `GROK_SESSION_ID`,
  `KIMI_SESSION_ID`, `KIMI_CODE_SESSION_ID`), and without a controlling terminal (perl opens `/dev/tty`); the
  PreToolUse hook (`boundcmd.luau`) refuses the obvious forms (`script`, `expect`, `unbuffer`, `./zn run --`, `sh -c
  'exec "$@"'`, `unset`/`env -u` of a marker). **Known weakness, not copied and not weakened here:** an agent that
  clears its own environment and gets a terminal passes the engine's check; a CLI that sets none of the listed markers
  is told only by the terminal tests (agy, which `.models.toml` supports, has no marker on the list: Unknowns, U6).
  **A second weakness found:** the Go program `z-nile/go/cmd/zn` runs the engine with `exec` and has no stdin test of
  its own, so a recording form started through it loses the launcher's layer (ticket C must carry it: C's guard table).
- The Go program (f0427, f0428 steps 1 to 4) embeds Lune and the engine (`znpack`'s `enginePaths`: `z-nile/engine`,
  `z-nile/lib`, `z-nile/vendor`, `z-nile/templates`, `z-nile/roots.luau`, `z-nile/affected.luau`), extracts them once
  to `<cache>/zn/<payload id>` (`ZN_CACHE`, else `XDG_CACHE_HOME`, else `~/.cache`), stamps `main.build` with the
  checkout's short HEAD, and runs `lune run <cache>/z-nile/engine/main -- <args>` by `exec` in the caller's folder,
  setting only `PATH`. Inside a host it runs a short allowlist; in this repository nothing calls it today. f0428's step
  8b (not built) is "the engine should run from absolute payload paths": `main.luau`, `light.luau`, `skills.luau`,
  `board.luau`, `ids.luau`, `dispatcher.luau` and others read `z-nile/...` relative to the folder they run in.

## Experiments run during this design (all read-only, or in `.cache/d0434-follow/` of this worktree)

- **E1, main's `zn` run from a worktree acts on the main checkout.** From `.worktree/d0434-follow/z-nile`,
  `/path/to/pickman/zn find d0434` printed `../../../z-nile/.tracker/issues/d0434` (the main
  checkout's copy) while `../zn find d0434` printed `.tracker/issues/d0434`. Pass for the question "does `<main>/zn`
  run in the caller's worktree": **no** (except `work`). Consequence: telling a worker "run the main checkout's zn"
  today would make `restack` read the main checkout's git dir and `git switch` layer branches in the main checkout
  (a layer not checked out elsewhere switches; one checked out in the raft's worktree fails). The interim sentence is
  only true after B1 changes main's launcher (B1, decision B-D1). The R0070 worktree's reflog (11:12:06 to 11:12:28
  PST) shows the old engine's `reset` to `ef5a0f42` and `rebase (abort)`, then the resolved commit `630772df` checked
  out again and rebased cleanly in that worktree; how the worker ran main's engine there could not be determined from
  the code (see "Could not determine" at the end).
- **E2, the Go program runs today's engine in an old worktree.** Built from this branch (5e8f5eaa4a1a), run at the top
  of `.worktree/R0070` (150 commits behind): `find c0194` and `guesses R0070` answered correctly with the embedded
  engine. Run from a subfolder it fails (`tracker find: no z-nile/projects.toml in .`): the Go front door does not
  change to the checkout's top or set `ZN_TOP` and `ZN_CWD` as the launcher does. Pass for "the embedded engine works
  on an old tree"; fail for "the Go program can replace the launcher as it is".
- **E3, build cost.** `znbuild.sh` with a warm Go cache: 0.4 s wall; with an empty `GOCACHE`: 3.5 s wall (13 s CPU);
  the binary is 15.9 MB; the payload is extracted once per content id (`~/.cache/zn/` now holds two ids side by
  side, so two versions on one machine coexist).
- **E4, a defect in `znbuild.sh`.** With a relative `--out` the script `cd`s into the Go module before `go build -o
  "$tmp"`, so the real binary lands in `z-nile/go/<out>` and the empty `mktemp` file is renamed onto `--out`; it
  prints "built" and exits 0. Reproduced twice; an absolute `--out` works. The selector lists no spec for
  `z-nile/lib/znbuild.sh` (a watch hole). Fixed in C1 (resolve `--out` to an absolute path first; a Go test builds
  with a relative path and checks the size).
- **E5, "same patch".** In a fixture repository: `git diff <base> <tip> | git patch-id --stable` of a layer and of its
  clean rebase onto a moved main are equal; after a rebase whose conflict was resolved they differ, and `git range-diff`
  pairs neither commit at its default creation factor. Pass for "patch-id tells an unchanged rewrite"; it cannot call a
  resolved rewrite "the same", so the design shows those as different and asks for more (A-D3).
- **E6, which `zn` the hook recognises.** `boundcmd.luau` treats a word whose basename is `zn` (or ends `/zn`, or names
  `engine/main`) as zn: an installed `~/.local/bin/zn` already counts for the background rule and the approve forms. No
  change is needed for that.

---

# Draft A: Restack cannot be told an old branch is ours (D1)

type: defect; project z-nile; tributary: delivery-and-landing; risk: risky (it changes when a branch on origin may be
overwritten); depends_on: []; size: ~580.

## Problem
- Since d0434, `./zn restack <R-id>` replaces origin's copy of a diverged layer only when `refs/zn/pushed/<layer>`
  names origin's tip, and a layer pushed before that rule (or from another clone) has no such ref and never gets one,
  so restack stops on every layer of every old raft that was rewritten locally.
- Evidence: on 2026-11-23 and 2026-11-24 restack stopped on R0070 (2 layers) and R0100 (5 layers), and R0080 and
  R0114 are next; each time the lead checked the commit by hand (author, date, subject, the diff being the same change
  as the local rewrite) and the owner typed `git update-ref refs/zn/pushed/<layer> <sha>` per layer, three times.
- No zn command performs that act, so the only way through is a hand-typed git command that nothing shows, checks or
  records, while workers rightly refuse to write the ref themselves.

## Non-goals
- No agent, worker or dispatched step may make this assertion, in any form; nothing here lowers the bar the approval
  record has.
- The command does not push, force, rebase, reset or move any branch or worktree; restack stays the only thing that
  publishes a layer, under its existing lease.
- It does not judge whose a commit is from its author field or its subject; it shows them to the person.
- It does not change `restackplan.trusted` or the lease logic.

## Solution
- One zn command, run by the person in a terminal, lists every layer of a raft whose origin tip restack would refuse
  as someone else's, and for each shows the branch, origin's commit id, author, commit date, subject, how many commits
  it is ahead of its base, the local tip, and whether the local layer's change is the same patch.
- It asks the person to confirm each layer (one by one, or all of the same-patch layers at once), and records
  `refs/zn/pushed/<layer>` at the commit it showed only for the layers confirmed.
- It records nothing for a declined layer, a layer whose origin tip moved since it was shown, or a layer whose ref
  changed since it was shown, and it never pushes, forces or rewrites anything.
- It refuses, with a message telling the agent to stop and ask the person, when run inside an agent session, under the
  dispatcher, inside a walkthrough session, or without a terminal, by the same standard as recording an approval.
- Restack's refusal of a diverged layer names this command and says an agent must stop and ask the person.

## Design

**The command: `./zn restack <R-id> --origin-is-mine`** (Guess G1). A mode of `restack` because it serves exactly one
refusal of restack, and its name is the assertion itself: "origin's branch is mine". Alternative: `--ours`, rejected
because in git "ours" and "theirs" name the sides of a conflict and `-s ours` discards the other side, so a worker
resolving a conflict could read `--ours` as "take my side"; and a separate command (`./zn vouch`), rejected because the
person would not find it from restack's refusal. It is not combinable with `--continue` or `--abort` (usage error).
`--origin-is-mine` joins the boolean flags in `main.luau`'s option parser (the list at `--continue`, `--abort`).

**Who may run it.** The person, by the approval standard, with nothing weaker and nothing copied loosely:
1. The launcher `zn`: the approve block becomes a list of person forms (`approve` recording forms, and `restack`
   with `--origin-is-mine` anywhere in its words); for each it refuses under `ZN_DISPATCH`, under
   `ZN_APPROVE_SESSION`, and when stdin is not a terminal, before Lune starts.
2. The engine: a new pure module `z-nile/engine/personact.luau` holds the one refusal function (the dispatcher, the
   walkthrough session, every `agentenv.MARKERS` entry, the controlling terminal) with the act's name and the command
   the person runs as parameters; `approvewalk.refuseAgent` and `approve`'s block in `main.luau` call it with the
   approve wording, so approve's messages stay byte for byte (its specs pin them), and restack's mode calls it with its
   own. One function, so the two acts cannot drift (lesson zz-test/one-rule-one-function).
3. The prompt is read from `/dev/tty`, as `approve --apply` reads its `y/N`, never from stdin.
4. The PreToolUse hook's rules (`boundcmd.luau`) add `restack ... --origin-is-mine` to the terminal forms it refuses
   (the same wrappers as approve). This changes what the hook refuses: **it must be shown to the owner before it
   lands** (Open to the human, O1); A1 is mergeable without it, since the engine is the guard.
The refusal happens before the fetch: a refused run reads and writes nothing.

**What it lists.** It fetches origin (`git fetch --quiet origin`: its only write besides the confirmed refs is the
fetch's own, `refs/remotes/origin/*`), then for each layer of the raft (`layergit.layersOf`) computes the same facts
restack does (`restackplan.source`, the `localExtra` and `originExtra` ancestry tests): a layer is listed when restack
would refuse it, that is local and origin both hold commits the other lacks and `restackplan.trusted` is false (no ref,
or a ref naming another commit). Every other layer is named once in the summary with why nothing is asked (Guess G6):
`not on origin` (restack creates it under a must-not-exist lease), `no local branch` (restack takes origin's),
`not diverged` (one side contains the other), `already yours` (the ref names origin's tip). Alternative: list every
layer without a ref, rejected: a ref for a layer restack never refuses asserts something nobody needed.

**What it shows, per listed layer.** Branch; origin's tip (12 hex), author name and email, committer date in the
local zone (`%cd` with `--date=format-local:%Y-%m-%d %H:%M %Z`), subject; the number of commits from the layer's base
to origin's tip; the local tip and its count; and "change: the same patch" or "change: DIFFERENT". The base on each
side is the base restack itself would use for that tip (`upstreamOf(layer, raft, tip, below)` with the layer below's
tip on the same side: origin's layer below for origin's tip, the local layer below for the local tip; `main`'s fetched
tip for layer 1), so the patch compared is the layer's own change. When the ref names an older commit, it also shows
`this clone last recorded <sha>`, and when that commit is an ancestor of origin's tip, the commits after it (up to 10,
`<sha> <author> <date> <subject>`, then `and N more`): those are what the person is vouching for.

**"Same patch"** (Guess G2) is `git diff <base> <tip> | git patch-id --stable` equal on both sides (E5: equal for an
unchanged rebase, different after a resolution). Alternative: per-commit patch ids (`git log -p | git patch-id`),
rejected because a finished layer is one commit locally but may be several on origin (review files after finish), and
the person cares about the layer's change, not its commit shape; tree equality, rejected because the bases differ
after main moved. When either side has no base or patch-id fails, it is shown as `change: cannot compare (<why>)` and
treated as DIFFERENT (fail closed).

**When the patch is different** (Guess G3), the layer is never covered by "all": the person reads the line
`read both first: git range-diff <o-base>..<o-tip> <l-base>..<l-tip>` and confirms by typing the layer's name; any
other answer records nothing. Alternative: the same `y/N` with a warning, rejected: a resolved rewrite is exactly when a
glance is not enough; refusing different patches outright, rejected: after a conflict resolution the patch always
differs (E5), and that is the case R0070 was in.

**The answers.** For a same-patch layer: `y` records it, `n` or Enter records nothing, `a` records it and every later
same-patch layer of this run (still asking each different one) (Guess G4), `q` stops (later layers are not asked and
not recorded). Each answer is applied when given, so an interrupted run keeps what was confirmed before it and nothing
after it.

**Recording.** For a confirmed layer, just before the write: `git ls-remote origin refs/heads/<layer>` must still
return the tip that was shown, else nothing is recorded for it and the message names both commits ("moved while you
were reading"). Then `git update-ref --create-reflog -m "zn restack <R> --origin-is-mine: confirmed by the person at
<tty>" refs/zn/pushed/<layer> <shown tip> <old value>`, where `<old value>` is the ref's value when shown (the zero id
when there was none): git refuses the write if anything changed the ref in between, and that refusal records nothing
and is reported. The reflog is the audit trail: `git reflog refs/zn/pushed/<layer>` shows who-said-so and when
(Guess G7; alternative a log file under `.cache`, rejected: a second record of one fact, and lost with the cache).
It also refreshes `refs/remotes/origin/<layer>` only through the fetch, never by hand.

**Where it runs** (Guess G5): anywhere in the repository, the main checkout included. The refs and the layer branches
are the repository's, shared by every worktree, and the command changes no working tree, index or HEAD, so the result
is the same from the main checkout, the raft's worktree or any other worktree. It is a ref write like `git fetch`, so
the main checkout's command list in zz-rules gains it. A restack in progress (a marker) is not touched: the next
`--continue` reads the new ref when it judges that layer.

**What the act asserts, said plainly to the person** (printed once before the first question): "A yes says: the
commit on origin is my own earlier work (pushed before zn recorded its pushes, or from another clone of mine), so my
local rewrite of this layer may replace it." What could go wrong if the person confirms a branch that is not theirs:
the next `./zn restack` pushes the local rewrite over it with `--force-with-lease` on exactly that tip, and the other
person's commit is no longer on the branch; it survives only in clones that fetched it and in GitHub's record of the
pull request for as long as GitHub keeps it, and zn has no way to bring it back. The lease still protects anything
pushed after the person looked (the ref names only the tip shown, and restack's lease is that tip). Known limit, as for
approvals: `git update-ref` is open to any process of the same user; the command, the hook and the skills make the
person's act the only sanctioned way, they do not make it the only possible one.

**Restack's refusal** keeps every word it has (the d0434 specs look for the layer, both tips and `fetch`) and appends:
`If origin's commit is your own (pushed before zn recorded its pushes, or from another clone of yours), the person can
say so in their own terminal: ./zn restack <R> --origin-is-mine. An agent must not run it and must not write
refs/zn/pushed: stop and ask the person.`

**Skills.** z-work step 3 and zz-execute Phase 5 step 2 gain one sentence each: a restack that stops because origin
holds a commit the local branch was never based on is the person's to answer; the worker shows the person the line
and the command, stops, and never writes `refs/zn/pushed` or runs `--origin-is-mine` itself. zz-rules' lifecycle
paragraph on `refs/zn/pushed` names the command, and its main-checkout list gains it.

### Scalability
One fetch, then per layer about eight git calls (rev-parse, two ancestry tests, two merge-bases, two diffs into
patch-id, one log) plus one `ls-remote` per confirmed layer: R0100's five layers are under a second. Nothing grows with
the number of rafts.
### Maintainability
The decisions (which layers to list, how to word each line, what each answer does, what a moved tip means) are pure in
`z-nile/engine/restackours.luau`; the git edge is in the same module's `run`, called from `restackcmd.run` for the new
mode. The person check has one home, `personact.luau`. `main.luau` gains no top-level local (the flag joins the
boolean list; `cmd.restack` passes the mode).
### Usability
Usage text: `restack <R-id> [--continue | --abort | --origin-is-mine]`. Every refusal names the act, why it is
refused, and the command the person runs. The exhaustive lists it joins: the option parser's boolean flags, the
launcher's person forms, the hook's terminal forms (owner first), zz-rules' main-checkout list and the restack row.

## The messages (exact text)

Before the first question (stdout):
```
R0100: 5 layers on origin hold commits that restack would not replace, because this clone has no record of pushing them.
A yes says: the commit on origin is my own earlier work (pushed before zn recorded its pushes, or from another clone of mine), so my local rewrite of this layer may replace it. A yes for someone else's commit lets the next ./zn restack R0100 push over it.
Answer for each: y yes, n no (the default), a yes to this and every later layer whose change is the same patch, q stop.
```
Per layer, same patch:
```
[1/5] R0100/1/c0265
  origin: 0f3abe130d1c  Philip Bergen <philip@example.invalid>  2026-11-18 14:02 PST  c0265: Work heartbeat and lost items
          1 commit after its base (origin/main at 3c1d2e4f5a6b)
  local:  7e8f9a0b1c2d  1 commit after its base (origin/main at 5e8f5eaa4a1a)
  change: the same patch (git patch-id of the layer's change matches)
Is origin's R0100/1/c0265 your own work? [y/N/a/q]
```
Per layer, different patch (the prompt changes):
```
  change: DIFFERENT: the layer's change on origin is not the change on your local branch.
  Read both first: git range-diff 3c1d2e4f5a6b..0f3abe130d1c 5e8f5eaa4a1a..7e8f9a0b1c2d
Type R0100/1/c0265 to say origin's commit is your own work; anything else records nothing:
```
An older ref:
```
  this clone last recorded 9a8b7c6d5e4f for this layer; origin has 2 commits after it:
    0f3abe130d1c Philip Bergen 2026-11-18 14:02 PST c0265: Work heartbeat and lost items
    1b2c3d4e5f6a Philip Bergen 2026-11-18 13:40 PST R0100: review-002
```
After each answer:
```
recorded: refs/zn/pushed/R0100/1/c0265 = 0f3abe130d1c
not recorded: R0100/2/c0274 (you said no)
not recorded: R0100/3/c0275: origin's tip moved from 1a2b3c4d5e6f to 9c8d7e6f5a4b while you were reading. Run ./zn restack R0100 --origin-is-mine again to see the new commit.
not recorded: R0100/4/c0276: refs/zn/pushed/R0100/4/c0276 changed while you were reading (now 6f31f21c9aaa). Run ./zn restack R0100 --origin-is-mine again.
```
Summary (last lines):
```
Recorded 4 of 5 layers. Nothing was pushed or moved. Next: ./zn restack R0100 (a worker may run it now).
Not asked: R0100/5/c0277 not diverged (origin's branch contains the local one).
```
or, with nothing confirmed:
```
Nothing recorded. ./zn restack R0100 will stop at R0100/1/c0265 as before.
```
or, with nothing to ask:
```
R0100: no layer needs this. Every layer is not on origin, has no local branch, is not diverged, or is already recorded as yours. Run ./zn restack R0100.
```
Refusals (exit 1, stderr, nothing fetched or written):
```
restack --origin-is-mine is refused inside an agent session (CLAUDECODE is set). Only the person may say that a branch on origin is theirs, because a yes lets restack replace what is there. Stop, and ask the person to run this in a terminal of their own: ./zn restack R0100 --origin-is-mine
restack --origin-is-mine is refused while ZN_DISPATCH is set. Write the question in questions.md and stop: the person runs ./zn restack R0100 --origin-is-mine in a terminal of their own.
restack --origin-is-mine is refused inside a walkthrough session (ZN_APPROVE_SESSION is set): an agent never says a branch is the person's. Ask the person to run ./zn restack R0100 --origin-is-mine in a terminal of their own.
restack --origin-is-mine is refused without a terminal on stdin. Run ./zn restack R0100 --origin-is-mine yourself, in a terminal.
usage: restack <R-id> [--continue | --abort | --origin-is-mine]
```
Restack's refusal, as amended (stderr, exit 1):
```
restack stopped at R0070/2/c0189: origin's branch (9f730e13d...) holds a commit that your local branch (4b5c6d...) was never based on, so it is someone else's work. Nothing was changed for this layer or any after it. To go on: git fetch, rebuild your commits on origin's tip (9f730e13d...) (rebase R0070/2/c0189 onto origin/R0070/2/c0189), then run ./zn restack R0070 again; or ask whoever pushed it. If origin's commit is your own (pushed before zn recorded its pushes, or from another clone of yours), the person can say so in their own terminal: ./zn restack R0070 --origin-is-mine. An agent must not run it and must not write refs/zn/pushed: stop and ask the person.
```

## Touched modules
- `z-nile/engine/restackours.luau` (new)
- `z-nile/engine/personact.luau` (new)
- `z-nile/engine/restackcmd.luau`
- `z-nile/engine/approvewalk.luau`
- `z-nile/engine/main.luau`
- `z-nile/engine/boundcmd.luau` (owner first, O1)
- `zn`
- `z-nile/skills/zz-rules/SKILL.md`
- `z-nile/skills/zz-execute/SKILL.md`
- `z-nile/skills/z-work/SKILL.md`
- `z-nile/tests/tooling/restackours.spec.luau` (new)
- `z-nile/tests/tooling/personact.spec.luau` (new)

## Affected specs
`lune run z-nile/affected --` per path (counts at 5e8f5eaa4): `restackcmd.luau` 4 (`restackplan`, `stack-land`,
`tributary-source`, `work-order-can`), `restackplan.luau` 10, `approvewalk.luau` 10, `agentenv.luau` 17,
`boundcmd.luau` 21, `main.luau` 305 and `zn` 139 (nearly every engine spec: the executor runs the affected gate),
`z-work/SKILL.md` 8, `zz-execute/SKILL.md` 3; plus the new acceptance spec `origin-is-mine.spec.luau` and the two new
tooling specs.

## Regression guard
- d0434's sequestered `restack-conflict.spec.luau` (AC9, AC21 look for the layer, both tips and `fetch` in the refusal:
  kept, text only appended); `stack-land.spec.luau`; `approve-hook.spec.luau`, `approve-walk.spec.luau` and
  `approval-facts.spec.luau` (approve's refusal texts must stay byte for byte through `personact`); the hook specs of
  `boundcmd` (`approve-hook`).
- Overrides: none (no promoted spec pins the refusal's full text or the absence of the flag; `grep -rlF zn/pushed
  z-nile/tests/acceptance` lists nothing).

## Unknowns & experiments
- U1 (pass/fail: does `git update-ref --create-reflog -m <msg> <ref> <new> <old>` write a reflog for a `refs/zn/` ref
  with the default `core.logAllRefUpdates`, and refuse when `<old>` is stale?) Method: a fixture repository under
  `.cache`, two writes, `git reflog <ref>`. Fallback: no reflog; the confirmation line goes to
  `<main>/.cache/restack-origin-is-mine.log` (one line per record, never read by any guard). Executor's Phase 1.
- U2 (does `upstreamOf` give origin's tip a base when origin's layer below is the old one?) Method: the R0100 shape in
  the acceptance fixture (origin's layers on an old main, local ones on the new). Fallback: `git merge-base <origin
  tip> <origin's layer below tip>`, and "cannot compare" when that fails.
- U3 (is the `[y/N/a/q]` read from `/dev/tty` testable in a spec?) Method: the walkthrough's `--apply` specs already
  drive a `/dev/tty` prompt (zz-test/terminal-fixtures-clear-the-agent-session): reuse their pseudo-terminal helper.
  Fallback: a test seam `ZN_TTY_IN=<file>` honoured only when `PICKMAN_FENCE_SPECS=1` (named in the spec, nothing else
  sets it), plus one end-to-end case under `script(1)`.
- U4 (E5 above, run): patch-id equal for a clean rebase, different after a resolution. Passed.

## Rules and mutants
| rule | spec :: case | mutant it kills | checked |
|---|---|---|---|
| only diverged, untrusted layers are asked | origin-is-mine :: AC1 | ask every layer without a ref; skip a layer whose ref is older | reasoned |
| each line shows sha, author, date, subject, counts, same/different | AC1 | omit the author or the count; compare commit ids instead of patches | reasoned |
| y records the shown tip; n and Enter record nothing | AC2 | default yes; record origin's current tip instead of the shown one | reasoned |
| a covers only same-patch layers | AC2, AC3 | `a` also records a different layer | reasoned |
| a different patch needs the layer's name | AC3 | accept `y` for a different layer | reasoned |
| refused for every agent marker, the dispatcher, the walkthrough session, no stdin terminal, no controlling terminal; before the fetch | AC4 | check one marker only; check after the fetch; read the answer from stdin | reasoned |
| a moved origin tip records nothing | AC5 | write without `ls-remote`; compare with the remote-tracking ref | reasoned |
| a ref changed meanwhile records nothing (compare-and-swap) | AC6 | `update-ref` without the old value | reasoned |
| a confirmed layer is then taken by restack under its lease; a declined one still stops | AC7 | restack ignores the new ref; the command pushes itself | reasoned |
| nothing pushed, no branch or worktree moved | AC8 | a `git push`, `switch` or `reset` in the mode | reasoned |
| same result from the main checkout and any worktree | AC9 | read the marker's git dir; refuse in the main checkout | reasoned |
| the refusal and the skills send an agent to the person | AC10 | text removed | reasoned |
| approve's refusal texts unchanged through `personact` | tooling personact.spec | reword one of approve's lines | reasoned |
All rows are `reasoned`: no prototype was built in this design-only task; the executor's mutation check fills them.

## Test plan
- `<A>/acceptance/origin-is-mine.spec.luau` (new, one shared fixture with a bare origin, a raft of four layers: one
  diverged same-patch, one diverged resolved, one not diverged, one not on origin; a second fixture clone writes
  someone else's commit) :: AC1 to AC11.
- `z-nile/tests/tooling/restackours.spec.luau` :: the pure listing, wording and answer table.
- `z-nile/tests/tooling/personact.spec.luau` :: each refusal of both acts; approve's texts exactly as today.

## Acceptance criteria
### Checked
- AC1: For a raft whose diverged layers have no ref or an older one, `--origin-is-mine` prints, for each such layer
  only, its branch, origin's tip, author, commit date, subject, commits after its base, the local tip and count, and
  whether the change is the same patch, and names every other layer once in its summary with the reason.
- AC2: `y` records `refs/zn/pushed/<layer>` at the tip shown, with a reflog line; `n` and Enter record nothing; `a`
  records the same-patch layers from there on and still asks each different one; `q` stops and keeps only earlier yeses.
- AC3: A layer whose change differs shows the `git range-diff` line and records only when the layer's name is typed.
- AC4: With any `agentenv` marker, `ZN_DISPATCH`, `ZN_APPROVE_SESSION`, stdin not a terminal, or no controlling
  terminal, it exits 1 with the message for that case naming the command the person runs, and fetches and writes
  nothing.
- AC5: When origin's tip moves between showing and confirming, nothing is recorded for that layer and the message names
  both commits.
- AC6: A layer whose ref names an older commit shows the commits after it; a confirmed write replaces exactly that old
  value; a ref changed by another process meanwhile is not overwritten.
- AC7: After a confirmation `./zn restack` replaces origin's layer with the local rewrite under the lease of the
  recorded tip; a declined layer still stops restack with the amended refusal.
- AC8: Before and after a run with every answer given, the refs (but `refs/remotes/origin/*` and the confirmed
  `refs/zn/pushed/*`), every worktree's HEAD and status, and origin are unchanged.
- AC9: The same fixture gives the same listing and the same writes when run from the main checkout and from the raft's
  worktree.
- AC10: Restack's refusal names `--origin-is-mine` and says an agent must stop and ask; z-work and zz-execute say the
  worker stops and asks and never writes `refs/zn/pushed`.
- AC11: Declining every layer prints "Nothing recorded" and the next restack stops as before.

The ticket's `check.sh` (to be written when the ticket is captured and its spec exists, in d0434's pattern: the spec
runs once, each line requires its named case):
```
SPEC="$A/origin-is-mine.spec.luau"
check "AC1: lists only the layers restack would refuse, with sha, author, date, subject, counts and same or different change" case_ok "AC1:"
check "AC2: y records the shown tip with a reflog line, n records nothing, a covers same-patch layers, q stops" case_ok "AC2:"
check "AC3: a different change shows range-diff and records only when the layer's name is typed" case_ok "AC3:"
check "AC4: refused for every agent marker, the dispatcher, a walkthrough session and without a terminal, before any fetch" case_ok "AC4:"
check "AC5: a tip that moved while the person read records nothing and names both commits" case_ok "AC5:"
check "AC6: an older ref shows the commits after it, and a ref changed meanwhile is not overwritten" case_ok "AC6:"
check "AC7: after a yes restack replaces origin's layer under the recorded lease; a no still stops it" case_ok "AC7:"
check "AC8: nothing is pushed and no branch, worktree or origin ref moves" case_ok "AC8:"
check "AC9: the same result from the main checkout and from the raft's worktree" case_ok "AC9:"
check "AC10: the refusal and the skills send an agent to the person" case_ok "AC10:"
check "AC11: declining everything records nothing and restack stops as before" case_ok "AC11:"
```
### Judged
- JC1: the messages above read as plain words to the owner, each saying what to do next (rubric: no term the owner
  would have to look up; every refusal and every "not recorded" line names the command that goes on).
### Observed
- OC1: the owner runs `./zn restack R0080 --origin-is-mine` (or R0114, whichever is next) once in a terminal of
  their own, confirms after reading the lines, and the worker's next `./zn restack` goes through.

## Implementation steps (slice A1, mergeable alone)
1. Commit the failing acceptance spec and the two tooling specs (red). 2. `personact.luau`, and approve's two callers
moved to it, approve's texts unchanged. 3. `restackours.luau` (pure, then `run`). 4. The flag, the usage and the mode
in `main.luau` and `restackcmd.run`; the amended refusal. 5. The launcher's person forms. 6. Skills. 7. The hook's
terminal form, only after the owner has seen it (O1). 8. The ticket's checks and the affected gate.

---

# Draft B: A worktree runs its own old zn (D2, interim cover)

type: defect; project z-nile; tributary: delivery-and-landing; risk: risky (it changes which engine runs a command on
real branches); depends_on: []; size: ~490.

## Problem
- `./zn` inside a raft's worktree runs that worktree's own engine, as old as its branch, so a raft-managing command run
  there (restack, finish, start, commit, done, work) uses rules main no longer has.
- Evidence: on 2026-11-24 a worker ran `./zn restack R0070` inside the R0070 worktree, 150 commits behind main: the
  old restack (from before d0434) reset layer 1 to origin's tip, moving the local branch off the worker's resolved
  commit `630772df4`, started the rebase over and aborted it on the conflict; the commit survived only because the
  restack marker still named it, and the worker restored the branch by hand and continued with main's engine. Old
  worktrees also cannot read today's `.models.toml`.
- Telling the worker to "run the main checkout's zn" is not safe today either: `<main>/zn <command>` changes to the
  main checkout before it starts (E1), so `restack` would read the main checkout's git dir and switch layer branches
  there.
- No engine notices that another engine moved a branch during a restack it recorded, so a newer engine continuing such
  a restack would rebase origin's tip and leave the resolved commit behind.

## Non-goals
- The worktree's own `zn` and engine from before this lands cannot be changed from main; they stay old until the branch
  contains main. B covers that gap; it does not close it (C does).
- B does not package or install anything (C does).
- B does not change what any command does, only which engine runs it and the folder it runs in.

## Solution
- Every command line zn prints for a worker to run next in a raft's worktree names a zn that runs main's engine, when
  that worktree's own `./zn` would run an older engine.
- The z-work and zz-execute skills say in one sentence which zn to run from inside a worktree and why.
- From the first worktree that contains this change, `./zn` in a linked worktree runs the main checkout's engine for
  the raft-managing commands whenever its own engine is behind origin/main's, staying in the worktree as its folder.
- A restack in progress refuses to go on when a layer's branch is not where the restack's marker last left it, naming
  where it was and how to put it back, so a newer engine never builds over a branch an older one moved.
- `restack` refuses in the main checkout.

## Design

**B-D1, main's launcher acts in the caller's worktree for raft-managing commands.** Today only `work` does this. The
`work` block of `zn` becomes a list: when the caller's folder is inside another worktree of the same repository (same
git common dir, a different top), the commands of the list run this launcher's engine with `ZN_TOP` and `ZN_CWD` set
to the caller's worktree and that worktree as the folder. The list (the raft-managing commands, each because it acts on
the worktree's own branches, index or tracker files): `work`, `start`, `finish`, `restack`, `commit`, `focus`, `done`,
`trace`, `check`, `guess`, `spend`, `sync`, `status` (with a target), `close`, `idea`, `new`, `renumber`, `migrate`,
`remap`, `fold`, `unfold`, `recombine`, `release`, `skills`. Not on it, each because it already acts in a fixed place:
`ready`, `stop`, `dispatch` (main checkout only: they refuse anywhere else, so handing them to a worktree would break
`<main>/zn ready` from a worktree, which works today), `approve` (it finds its place itself, from anywhere), `worktree`,
`worktree-prune` (they act on the main checkout's `.worktree/`), `run`, `live`, `app` (handled before the engine), and
the read-only commands (`list`, `find`, `members`, `busy`, `audit`, `lessons`, `guesses`, `capture`, `metrics`, `board`,
`prompt`, `status` without a target, `workstreams`, `raft-plan` without `--apply`, `promote-check`, `model`, `rounds`),
whose printed paths are relative to the folder today and would change meaning. Alternative: every command, rejected for
the main-only ones above. With this, `<main>/zn restack R0070 --continue` from the R0070 worktree runs main's engine on
the R0070 worktree, and the sentence below is true.

**B-D2, restack refuses in the main checkout** of a repository with an origin, as `new` and `status` do: "restack must
run inside the raft's worktree: cd "$(./zn worktree R0070)"". It switches layer branches, which the main checkout never
does. (Every spec that runs restack runs it in a fixture's worktree: `stack-land`, `live-events`, `f0399/on`, d0434's;
U3 confirms.)

**B-D3, printed commands** (choice (a), Guess G8). The printed form stays `./zn`: 345 mentions in the skills, about 380
in the engine and 32 promoted acceptance specs that assert `./zn ...` texts would otherwise change, each needing an
override chore, and in every worktree that has B2's launcher `./zn` is already right. The one case it is wrong is a
worktree whose `./zn` is old. So the engine's two output edges for next steps (`fail`'s message and `work next`'s action
line) pass through `znname.rewrite(text, facts)`, which replaces each `./zn ` with `<main>/zn ` (the absolute path of
the main checkout, computed on this machine from `mainRoot()`, never stored) only when the worktree where the line will
be run is stale: its `zn` file has no hand-over line (`# zn: hands raft-managing commands to main's engine (B2)`) and
its HEAD lacks a commit of origin/main that touches the engine paths (`git rev-list --count
HEAD..refs/remotes/origin/main -- z-nile/engine z-nile/lib z-nile/templates z-nile/vendor z-nile/roots.luau
z-nile/affected.luau zn` > 0). The worktree is the raft's (`<main>/.worktree/<R>`) for `work next <R>`, else the
current one. In a fixture the worktree's launcher is the tree's own (with the hand-over line) so nothing changes and no
spec's text changes; d0434's sequestered texts (`./zn restack R0010 --continue`) stay as they are. Alternative 1: say
`zn` everywhere (the coordinator's suggestion), rejected for the cost above, and because it names a program that does
not exist until C; C revisits it. Alternative 2: thread a prefix parameter through every message builder, rejected:
some forty builders and their specs for one fact the edge knows.

**B-D4, the skill sentence** (choice (b)), in z-work step 3 and zz-execute Phase 0 step 1: "Run zn exactly as zn prints
it: inside a raft's worktree a line may name the main checkout's zn (`<main checkout>/zn`) instead of `./zn`, because
that worktree's own `./zn` is as old as its branch and would run an older engine; never run a worktree's own `./zn`
for restack, finish, start, commit or done when its branch is behind main."

**B-D5, the restack marker detects another engine** (choice (d)). The marker gains `writer <id>` (the short HEAD of
the checkout whose engine wrote it, or the installed build's id under C), informational only (old markers parse: the
key is optional). The real detection needs no cooperation from the old engine: `--continue`, and a plain restack that
finds a marker with a rebase in progress or a `red` line, first compare each layer's local branch with the marker: a
branch at none of `orig`, `left` and `pushed` for its layer "moved since the restack left it", and the run refuses,
changing nothing, naming the layer, where the marker left it, where it is now, and the way back. A new engine thus never
rebases origin's tip over a resolved commit that an old engine moved aside (the 2026-11-24 case: layer 1's `left` was
`630772df4`, the branch was at `ef5a0f42`). Alternative: a version number that makes older engines refuse a newer
marker, impossible for engines that already exist; refusing every marker without `writer`, rejected: it would stop
every restack in progress the day this lands.

**B-D6, the hand-over in new worktrees** (choice (c), slice B2). The launcher, run as a linked worktree's own `./zn`
(caller is its own top), outside spec runs (`PICKMAN_FENCE_SPECS` unset), for a command of B-D1's list:
- runs its own engine when its HEAD has every engine commit of origin/main (choice (e) as the trigger: "behind by at
  least one commit that touches the engine paths");
- else execs the main checkout's `zn` with the same arguments, the folder unchanged, after one stderr line (B-D1 makes
  that act in this worktree);
- refuses instead, naming the fix, when the main checkout's engine is itself behind origin/main (`zn sync` there first,
  Guess G10), has uncommitted changes in the engine paths, or its `zn` is missing.
`ZN_ENGINE=tree` makes the launcher run its own engine anyway and prints one stderr line every time; a raft-managing
command under it is refused while the tree is behind origin/main's engine (Guess G11), so a developer can run an older
or changed engine only on commands that change nothing. Read-only commands always run the tree's own engine (the gate's
`./zn skills --check` and `./zn reap --auto` keep judging the branch). The hand-over line `# zn: hands raft-managing
commands to main's engine (B2)` is what B-D3 reads. Cost: two `git rev-list --count` calls (the tree, the main
checkout), tens of milliseconds, only for the listed commands in a linked worktree.

**B-D7, the hook seatbelt for the gap** (optional, owner first, O1): the PreToolUse rules refuse `./zn <listed command>`
when the session's folder is a linked worktree whose `zn` lacks the hand-over line and whose HEAD is behind origin/main's
engine, with the message below. The hook runs from the session's project, which is the main checkout for a z-work
session, so its code is current even when the worktree is not: it is the one guard that reaches an old worktree. It
covers Claude Code sessions only (other CLIs have no such hook).

**What covers the gap that cannot be closed** (a worktree from before B2, until its branch contains main): the printed
lines (B-D3) and the skill sentence (B-D4) point the worker at main's zn; the marker check (B-D5) stops a newer engine
from building on what an older one moved; the hook (B-D7, if the owner agrees) refuses the old `./zn` in Claude Code;
and from C on, the installed `zn`, whose engine never depends on the folder. Nothing stops a person or agent from typing
the old `./zn` by hand outside Claude Code.

**Shared state old and new engines both write** (and whether a new engine misreads an old one's writes):

| state | writers | misread? |
|---|---|---|
| `refs/zn/pushed/<layer>` (shared refs) | `start`, `finish`, `restack` after a push (d0434 on) | no: same format; engines before d0434 never write it (the cause of D1) |
| restack marker `<worktree git dir>/zn-restack.state` | `restack` (d0434 on) | no for d0434-on engines (unknown keys ignored); an engine before d0434 ignores it and moves branches (the D2 incident): B-D5 |
| layer branches, the in-progress rebase | restack, finish, start, by hand | an old restack resets a local branch to origin's tip (before d0434): B-D5 and B-D6 |
| `.cache/work/carriers.tsv` (main checkout) | `work next` (f0399 on), one line `<id>\t<session>\t<epoch>` | no format change found since f0399; an older engine does not write it |
| the live daemon's state `.cache/live/`, socket | `./zn live` | built from the main checkout's Go even by a worktree's launcher; a launcher from before f0424 has no `live` (the engine reports an unknown command) |
| `.models.toml` (tracked, read per branch) | by pull request only | yes, the known case: an old engine cannot read the new `[clis.*]` shape; a new engine still reads the old shape |
| `spend.d/<writer>.tsv`, `.cache/measure.tsv` | `commit`, `spend`, `done`, the gate | no: nine or ten columns, both read |
| `approval.md` hashes | `approve` | not checked: an old engine's hash of the contract may differ from a new one's, so `done` could call an old-engine approval stale (U4) |
| `.cache/approve/<run>/`, `.cache/dispatch/` | the walkthrough, the dispatcher | main-checkout-only commands, so the main checkout's engine |

### Scalability
B-D3 adds one file read and at most one `git rev-list` per printing command, only when the current folder is a linked
worktree; B-D6 two `rev-list` calls per listed command in a linked worktree.
### Maintainability
The list of raft-managing commands has one home, a shell array in `zn` mirrored by `z-nile/engine/znname.luau` (pure:
the rewrite and the stale test) and pinned equal by a spec (one-rule-one-function). The marker check is
`restackplan.movedSince`, already used by `--abort`.
### Usability
The messages below; zz-rules' Worktrees section says which zn a worktree runs.

## The messages (exact text)
B-D6, on stderr before the hand-over:
```
zn: this worktree's engine is 37 engine commits behind origin/main, so restack runs with the main checkout's zn (/path/to/pickman/zn), here in this worktree.
```
B-D6 refusals (exit 1):
```
zn: this worktree's engine is behind origin/main, and so is the main checkout's (/path/to/pickman). Run /path/to/pickman/zn sync (it fast-forwards the main checkout), then run ./zn restack R0070 again.
zn: this worktree's engine is behind origin/main, and the main checkout has uncommitted changes in its engine (z-nile/engine/restackcmd.luau). Nothing ran. Ask the person: the main checkout is never edited.
zn: ZN_ENGINE=tree: running this worktree's own engine (/path/to/pickman/.worktree/R0070, 3c1d2e4f5a6b), not main's.
zn: ZN_ENGINE=tree refuses restack here: this worktree's engine is 37 engine commits behind origin/main, and an older engine must not change a raft. Merge origin/main into this branch (./zn sync), or run the command without ZN_ENGINE.
```
B-D2:
```
restack must run inside the raft's worktree: cd "$(./zn worktree R0070)"
```
B-D5 (exit 1, nothing changed):
```
restack of R0070 cannot go on: R0070/1/c0194 is at ef5a0f42a825, but this restack left it at 630772df4e1b (its marker was written by zn 9d8c7b6a5f4e). Something else moved it, perhaps an older zn (a worktree's own ./zn). Nothing was changed. If 630772df4e1b is your work, put the branch back (git switch R0070/1/c0194 && git reset --hard 630772df4e1b), then run /path/to/pickman/zn restack R0070 --continue; or ./zn restack R0070 --abort to put every branch back.
```
(The `--continue` command in that line is printed through B-D3, so it names main's zn exactly when the worktree is
stale.)
B-D7, the hook (if the owner agrees):
```
./zn restack in this worktree runs its own engine, which is behind origin/main (this branch predates the hand-over). Run it as /path/to/pickman/zn restack R0070, which runs main's engine here.
```
B-D3, a `work next` line for a stale R0070 worktree:
```
restack R0070: Run /path/to/pickman/zn restack R0070, then ask again.
```

## Touched modules
- `zn`
- `z-nile/engine/znname.luau` (new)
- `z-nile/engine/main.luau`
- `z-nile/engine/work.luau`
- `z-nile/engine/restackcmd.luau`
- `z-nile/engine/restackplan.luau`
- `z-nile/engine/boundcmd.luau` (B-D7, owner first)
- `z-nile/skills/z-work/SKILL.md`
- `z-nile/skills/zz-execute/SKILL.md`
- `z-nile/skills/zz-rules/SKILL.md`
- `z-nile/tests/tooling/znname.spec.luau` (new)
- `z-nile/tests/tooling/zn-handover.spec.luau` (new)

## Affected specs
`zn` 139, `main.luau` 305, `work.luau` 51, `restackplan.luau` 10, `restackcmd.luau` 4, `boundcmd.luau` 21 (the affected
gate), plus the new acceptance spec `worktree-zn.spec.luau` and the two tooling specs.

## Regression guard
- `work-*.spec.luau` (the `work` hand-over to a caller's worktree keeps its behaviour: `ZN_TOP`, `ZN_CWD`, the folder);
  `stack-land`, `live-events`, `f0399/on.spec.luau` (restack in fixture worktrees, no hand-over under
  `PICKMAN_FENCE_SPECS=1`); d0434's sequestered spec (markers without `writer` still work; printed texts unchanged in
  fixtures); `c0114`'s layout spec and `c0120/finished.spec.luau` (they read or write a `zn` file as text: the new
  lines must not break what they look for: U5).
- Overrides: none found (`grep -rlF` of `zn-restack.state` and of the hand-over line in `z-nile/tests/acceptance`
  list nothing; no promoted spec asserts that restack runs in a main checkout).

## Unknowns & experiments
- U1 (E1, run): `<main>/zn` from a worktree acts on the main checkout. Confirmed; B-D1 is the fix.
- U2 (does `exec "$main/zn" "$@"` from a worktree's launcher keep the folder, stdin and the exit code, and does B-D1
  then pick the caller's worktree?) Method: a fixture repository with two worktrees under `.cache`, a fake engine that
  prints `pwd -P`, `$ZN_TOP`, `$ZN_CWD`. Fallback: run `lune run "$main/z-nile/engine/main"` directly from the worktree
  launcher with the variables set, as the `work` block does.
- U3 (does any spec run `restack` in a fixture's main checkout?) Method: `grep -n '"restack"' z-nile/tests -r` (read
  for this design: all are in `wt`, `wtD`, `wtR`), then the affected gate. Fallback: those cases move into a worktree.
- U4 (does an old engine's `approval.md` hash match a new engine's for the same contract?) Method: hash one approved
  ticket with the engine at an old commit and at main (`approve <id> --check` in two checkouts). Fallback: none needed
  for B; record the answer under C's staleness rules.
- U5 (which promoted specs read the root `zn` as text?) Method: `grep -rlE 'readFile.*zn|TOP}/zn' z-nile/tests`
  (`c0114/layout`, `c0120/finished`, `c0115/docs`, `c0115/trusted-base`, `c0117/docs` matched), read each. Fallback: an
  override chore for one that pins the launcher's lines exactly.
- U6 (does an agy session set an environment variable that tells it is an agent, and does its tool shell have a
  controlling terminal?) Method: inside an agy session, `env | sort` and `perl -e 'open(my $f,"<","/dev/tty") or exit
  1; exit(-t $f?0:1)'; echo $?`. Fallback: add its marker to `agentenv.MARKERS` (A's guard then covers it); if it has
  none and has a terminal, say so to the owner as a known limit of both acts.

## Rules and mutants
| rule | spec :: case | mutant it kills | checked |
|---|---|---|---|
| main's launcher runs the listed commands in the caller's worktree | worktree-zn :: AC1 | keep `cd "$top"` for restack | reasoned |
| ready, stop, dispatch from a worktree still act in the main checkout | AC1 | hand every command over | reasoned |
| restack refuses in the main checkout | AC2 | no refusal | reasoned |
| a branch at none of orig, left, pushed stops `--continue` and a plain restack | AC3 | check only in `--abort`; compare with `orig` only | reasoned |
| a marker without `writer` still works | AC4 | require `writer` | reasoned |
| printed lines name main's zn only for a stale worktree | AC5 | rewrite always; never; judge the current folder instead of the raft's worktree | reasoned |
| a behind worktree's new launcher hands listed commands to main's zn; an up-to-date one runs its own; read-only commands run their own | AC6 | hand over when up to date; hand over read-only commands | reasoned |
| a main checkout behind or dirty in the engine refuses with the fix | AC7 | hand over anyway | reasoned |
| `ZN_ENGINE=tree` prints its line, refuses listed commands while behind | AC8 | silent switch; allow restack while behind | reasoned |
| no hand-over in a spec run | AC9 | hand over under `PICKMAN_FENCE_SPECS=1` | reasoned |
| the skills say which zn | AC10 | sentence removed | reasoned |
| the list in `zn` equals `znname`'s | tooling znname.spec | add a command to one list only | reasoned |

## Test plan
- `<B>/acceptance/worktree-zn.spec.luau` (fixture: a bare origin, a main checkout, a raft worktree whose branch carries
  an older copy of the launcher and engine, made by checking out an old commit of the fixture's own history, and one
  carrying the new launcher) :: AC1 to AC10, and AC11 if the owner agrees to B-D7.
- `z-nile/tests/tooling/znname.spec.luau` :: the rewrite and the stale test, pure.
- `z-nile/tests/tooling/zn-handover.spec.luau` :: the launcher's decisions with a fake engine.

## Acceptance criteria
### Checked
- AC1: `<main>/zn` run from a linked worktree runs restack, finish, start, commit, done and work in that worktree (the
  marker is the worktree's, no branch of the main checkout moves), and ready, stop and dispatch still in the main
  checkout.
- AC2: `restack` refuses in the main checkout of a repository with an origin, naming the worktree command.
- AC3: With a restack marker, `--continue` and a plain restack refuse when a layer's branch is at none of the marker's
  tips for it, naming the layer, both tips and the way back, and change nothing.
- AC4: A marker gains `writer`; a marker without it is read and continued as before.
- AC5: `work next <R>` and restack's refusals print `<main>/zn` for a raft whose worktree's launcher is old and behind
  origin/main's engine, and `./zn` otherwise.
- AC6: A new launcher in a worktree behind origin/main's engine hands each listed command to main's zn with one stderr
  line and the worktree as its folder; up to date, or for a read-only command, it runs its own engine.
- AC7: When the main checkout's engine is behind origin/main or has uncommitted engine changes, a hand-over is refused
  with the message naming the fix.
- AC8: `ZN_ENGINE=tree` prints its line every time and refuses a listed command while the tree is behind.
- AC9: Under `PICKMAN_FENCE_SPECS=1` the launcher never hands over.
- AC10: z-work and zz-execute say which zn to run inside a worktree and why.
- AC11 (only if the owner rules for B-D7): the hook refuses `./zn <listed command>` in a stale worktree, naming main's zn.

`check.sh` lines (added with the spec):
```
SPEC="$A/worktree-zn.spec.luau"
check "AC1: main's zn run from a worktree acts in that worktree for the raft commands, and in the main checkout for ready, stop and dispatch" case_ok "AC1:"
check "AC2: restack refuses in the main checkout" case_ok "AC2:"
check "AC3: a branch moved since the restack left it stops continue and restack, changing nothing" case_ok "AC3:"
check "AC4: the marker's writer line is optional" case_ok "AC4:"
check "AC5: printed commands name main's zn only for a stale worktree" case_ok "AC5:"
check "AC6: a behind worktree hands the raft commands to main's zn; an up-to-date one runs its own" case_ok "AC6:"
check "AC7: a main checkout behind or dirty in its engine refuses the hand-over with the fix" case_ok "AC7:"
check "AC8: ZN_ENGINE=tree is loud and refuses raft commands while behind" case_ok "AC8:"
check "AC9: no hand-over inside a spec run" case_ok "AC9:"
check "AC10: the skills say which zn to run inside a worktree" case_ok "AC10:"
```
### Observed
- OC1: the next worker that resumes an old raft (R0080 or R0114) is told `<main>/zn restack <R>` by `work next`, runs
  it from the raft's worktree, and the restack runs main's engine there.

## Implementation steps
- **Slice B1** (the owner's slice 1: printed commands and the skill sentence, with the two changes they need to be
  true): B-D1 (main's launcher), B-D2, B-D3 (`znname.luau`, the two output edges), B-D4, B-D5. Mergeable alone: it
  changes only what main's own zn does and prints.
- **Slice B2** (the owner's slice 3: the hand-over): B-D6 in the launcher with the hand-over line; B-D7 only after the
  owner has seen it. Mergeable alone after B1.

---

# Draft C: zn is one installed program with its own lifecycle (D2's fix)

type: feature; project z-nile; tributary: delivery-and-landing (or omarchy: Guess G20); risk: risky (it replaces how
every command starts); depends_on: [] (it takes over f0428 step 8b for this repository: O3); size: ~1,450.

## Problem
- Which engine runs a zn command depends on the folder and branch it is typed in: a worktree's `./zn` runs that
  branch's engine (D2's incident, Draft B), and the Go program that carries an engine of its own (f0427, f0428) is used
  only inside a host repository.
- The Go program cannot yet stand in for `./zn` in this repository: it does not set `ZN_TOP`/`ZN_CWD` or start at the
  checkout's top (E2), it drops the launcher's stdin test for recording an approval, and its engine still reads
  templates, `fence.sh`, `measure.pl` and other helpers from the folder it runs in (f0428 step 8b).
- Nothing installs it, names its version against the repository's main, tells a session that it is older than main,
  or upgrades it; and `znbuild.sh` with a relative `--out` reports success and writes an empty file (E4).

The owner's ruling (2026-11-24, verbatim): "This is why I want zn to be a go executable with its own lifecycle".

## Non-goals
- No agent downloads an executable; zn is only ever built locally from this repository's merged main.
- The gate, the spec runner and a ticket's `check.sh` keep testing the tree's own code; the installed engine never
  stands in for the code under test.
- No change to what any command does, only to how it is started.
- Not a rewrite of the engine in Go (f0427's later work); the engine stays Luau inside the program.

## Solution
- A person installs zn once from the repository (`./zn upgrade`, which builds it from origin/main's commit and puts it
  at `~/.local/bin/zn`), and the same command, as `zn upgrade`, upgrades it.
- `zn version` names the commit it was built from and a hash of its engine, and says whether that engine is the one on
  the repository's origin/main, older, newer, or not built from it.
- Started anywhere in this repository, the installed zn runs its own embedded engine, never the tree's, with the same
  folder, variables and guards the `./zn` launcher gives today.
- A command that changes a raft or tracker state refuses while the installed engine is older than origin/main's, naming
  `zn upgrade`; a read-only command prints one line and runs.
- `ZN_ENGINE=tree` runs the tree's engine instead, says so in one line every time, and refuses a state-changing command
  unless the tree contains origin/main's engine.
- The engine reads its own helper files from the payload it was extracted from, never from the folder it runs in;
  only the gate, the spec runner and `check.sh` files read the tree's.
- The repository's `./zn` becomes a shim that hands every command to the installed zn, keeping the tree's engine for the
  gate, the spec runner and `ZN_ENGINE=tree`, and falling back to Draft B's rule when zn is not installed.

## Design

**C-D1, building and installing.** One script, `z-nile/lib/znupgrade.sh`, run from a build worktree: it fetches
origin, creates or reuses a detached sparse worktree `<main>/.worktree/.zn-build` at `refs/remotes/origin/main` with
only `z-nile/` checked out (5,438 of 7,777 files), runs that tree's own `znbuild.sh --out <absolute temp path>`, checks
the result (`<temp> version` answers and names that commit), and renames it onto `$ZN_BIN_DIR/zn` (default
`~/.local/bin`, Guess G12) in one `rename`, so a running session never sees half a file. The upgrade logic that runs is
origin/main's own (the script is taken from the build worktree, not from the caller's branch). Bootstrapping is
`./zn upgrade` in the main checkout (the launcher's new case, before Lune); afterwards `zn upgrade` (the Go program runs
the same script from its build worktree). It refuses to install an older build than the installed one (`zn: the
installed zn (<sha>) is newer than this clone's origin/main (<sha>): git fetch origin first`) unless `--older`.
Alternatives: `go install` into `GOBIN`, rejected: it builds whatever tree it is run in and embeds no payload; a
`./zn install` that copies a binary built from the main checkout's files, rejected: the main checkout may be behind or
edited, and origin/main is the reviewed code (Guess G13). E3: about 0.4 s with a warm Go cache, 3.5 s cold.

**C-D2, the version.** `znbuild.sh` stamps, besides `main.build=<short HEAD>`, `main.engine=<hash>`: the sha256 of the
git tree ids of the packed paths at the build commit (`git rev-parse <commit>:<path>` for each of `znpack`'s
`enginePaths`, plus `zn`), so two clones and two machines compute the same value from content alone; a dirty build has
no engine hash (`engine dirty`). `zn version` prints `zn <build> engine <hash> <os>/<arch> payload <id> lune <sum> (<pin>
pin)` and, inside a repository, one more line: `origin/main's engine: <hash> (current | older: N engine commits behind,
zn upgrade | newer than this clone's origin/main: git fetch origin | not built from this repository's main: zn
upgrade)`. Guess G16.

**C-D3, staleness on every command** (Guess G14). The Go front door computes origin/main's engine hash with one `git
rev-parse` of seven paths (a few milliseconds) and compares. Equal: run. Behind (the build commit is an ancestor of
origin/main, or the commit is unknown and the hashes differ): a state-changing command (Draft B's list plus `ready`,
`stop`, `dispatch`, `approve`'s recording forms, `restack --origin-is-mine`, `worktree`, `worktree-prune`) refuses with
`zn upgrade`; a read-only one prints one line and runs. Newer than this clone's origin/main: runs, with the line `git
fetch origin`. Not in a repository: runs. Alternatives: upgrade by itself before the command (rejected: a binary that
replaces itself mid-session while another session runs it, and a few seconds of build inside an unrelated command,
surprise the person); warn only (rejected: the D2 incident was an old engine run with a warning nobody reads). The
bottleneck: about ten merges a day touch the engine, so each machine meets the refusal about ten times a day and pays
one `zn upgrade` of a few seconds each time; any session may run it (Guess G15, O2), so it never waits for the person.

**C-D4, which engine runs in this repository.** Always the embedded one, whatever the folder or branch, so an old
worktree gets the installed engine and the incident cannot recur through `zn`. `ZN_ENGINE=tree` is the one switch: the
front door then execs the tree's `./zn` with `ZN_ENGINE=tree` kept, and the tree's launcher prints `zn: ZN_ENGINE=tree:
running this tree's engine (<top>, <short HEAD>), not the installed one (<build>)` every time; a state-changing command
under it refuses unless the tree's HEAD contains every engine commit of origin/main (Guess G11: a developer may run
their newer engine on their own raft, never an older one). The gate (`z-nile/check.sh`) and the spec runner export
`ZN_ENGINE=tree` for everything they start, and the line is not printed while `PICKMAN_FENCE_SPECS=1` or
`ZN_MEASURE_KIND=test` is set (they are the tree's own tests: Guess G17).

**C-D5, what `./zn` becomes** (Guess G17). A shim, still at the repository root: `run` (the bounded runner) and `live`
/ `app` stay in shell as today; under `ZN_ENGINE=tree` or `PICKMAN_FENCE_SPECS=1` it runs the tree's engine as the
launcher does now; otherwise, when `zn` is on PATH and is the installed program (its `zn version` names an engine
hash), it execs it with the same arguments and folder; when it is not installed, it keeps Draft B's behaviour and
prints once per session `zn is not installed: ./zn upgrade installs it (SETUP.md)`. Old worktrees' `./zn` stay old
(Draft B's cover); the installed zn is never started by an old shim, so it needs no refusal for one, and a new shim
passes `ZN_VIA_SHIM=1` only so `zn version` can say how it was reached. Alternative: remove `./zn` (rejected: specs
copy it into every fixture, the gate calls it, and a fresh clone needs a way in before zn is installed); keep `./zn` as
the tree's engine for everything (rejected: the owner's ruling). The printed form stays `./zn` (Draft B, G8): in every
tree that has the shim it reaches the installed zn. When the shim is everywhere (every open raft has merged main), a
later chore may switch the printed form and the skills to `zn`; not part of C.

**C-D6, the engine reads its own files from the payload** (f0428 step 8b, done here for this repository, O3). The
front door sets `ZN_PAYLOAD=<cache>/zn/<id>`; one helper, `z-nile/engine/payloadpath.luau` (`payloadpath.of(rel)`:
`ZN_PAYLOAD .. "/" .. rel` when set, else `rel`), is the one reader of that variable, and every engine read or spawn of
its own files goes through it: `TEMPLATES` and the board's `board.html` and `vendor`, `fence.sh`, `measure.pl`,
`bounded.pl`, `light.luau`'s file list, `skills.luau`'s and `dispatcher.luau`'s skill paths where they mean zn's own
skills, `ids.luau`'s counter path stays the tree's (it is tracker data). What stays the tree's on purpose: the spec
runner (`tests/run`), the affected selector when it selects the tree's specs for `finish`, `done` and the gate, `check.sh`
and `ac.sh` (the tree's acceptance), the projects' registry and tracker files. A spec pins the list (every literal
`"z-nile/` in the engine is either through `payloadpath` or on the tree list, read from the code with comments and
strings handled: zz-test/source-text-pins-read-the-code).

**C-D7, front-door parity** (lesson z-design/moved-work-names-how-each-guard-is-carried). What the launcher does today
and where each goes:

| launcher today | after C |
|---|---|
| `cd` to the checkout's top, `ZN_TOP`, `ZN_CWD` (E2 fails without it) | kept: the Go front door does the same (`git rev-parse --show-toplevel` of the caller's folder) |
| `work` from another worktree reads that worktree | kept: the caller's worktree is always the one used (there is no "launcher's own" tree any more) |
| approve's recording forms refused under `ZN_DISPATCH`, `ZN_APPROVE_SESSION`, stdin not a terminal | kept in Go before the engine, for the same forms plus `rework` and `restack --origin-is-mine` (`terminalOf(os.Stdin)`); the engine's own checks unchanged |
| the engine's CPU limit (`ZN_ENGINE_CPU`, default 1800 s) | kept: `setrlimit(RLIMIT_CPU)` lowered only, before the exec |
| `PATH` with `~/.rokit/bin` first | kept after the payload's `bin` (stylua, selene and rojo still come from rokit) |
| `run`: the bounded runner with the measurement variables | kept in the shim; the Go front door runs the payload's `bounded.pl` the same way |
| `live`, `app`: znlive built from the main checkout | kept: the front door execs the shim's code path for them (unchanged) |
| the PreToolUse hook's recognition of `zn` | unchanged: a basename `zn` already counts (E6) |

**C-D8, the guards.** The runner's jail, fence and tripwire: unchanged; specs never reach the installed zn (C-D5's
spec-run rule), and the installed zn writes only its cache folder (`~/.cache/zn`, outside every repository) and the
build worktree `<main>/.worktree/.zn-build` (under `.worktree/`, a git worktree like any other, ignored). A spec that
proves C-D5 uses a fake `zn` on PATH under `.cache`. The hooks in `scripts/hooks/` (`pre-bash.sh`, `post-edit.sh`,
`session-end.sh`) run `lune run z-nile/...` from the session's project and name no `zn` path; nothing in them must
change for C. Optional, owner first (O1): the hook could refuse a bare `./zn` in a tree without the shim (B-D7 covers
it). `./zn run` bounded commands: unchanged. The PreToolUse rule that a background call may hold only the gate, `zn`
commands and `check.sh` files: an installed `zn ...` already matches (E6).

**C-D9, commands and the engine each uses.**

| command | engine | why |
|---|---|---|
| every tracker and raft command (`work`, `start`, `finish`, `restack`, `commit`, `done`, `ready`, `stop`, `sync`, `status`, `approve`, ...) | installed | the rules that decide what happens to a raft are main's |
| `check <id>` | installed engine, the tree's `check.sh`, `ac.sh` and specs | the engine only starts the check; what is tested is the tree |
| `finish`, `done` (their affected specs, the gate) | installed engine, the tree's gate and specs | same |
| `z-nile/check.sh` (the gate) and `lune run tests/run` | the tree's, and `./zn` under it is the tree's (`ZN_ENGINE=tree`) | they test the tree |
| `run`, `live`, `app` | shell, as today | no engine |
| `upgrade`, `version`, `init` | Go | no engine |

## The messages (exact text)
```
zn 5e8f5eaa4a1a engine 7c41d0e2a9f3 darwin/arm64 payload a13c8e474c72ed2b lune e4cc1b42a45e5f6f (bin pin)
origin/main's engine: 7c41d0e2a9f3 (current)
origin/main's engine: 0d9e8f7a6b5c (older: zn is 3 engine commits behind origin/main; run zn upgrade)
zn: this zn is 3 engine commits behind origin/main (built from 5e8f5eaa4a1a), so it does not run restack, which changes a raft. Run zn upgrade (it builds zn from origin/main in a few seconds; any session may run it), then run zn restack R0070 again.
zn: this zn is 3 engine commits behind origin/main (built from 5e8f5eaa4a1a); zn upgrade brings it up to date.
zn: the installed zn (5e8f5eaa4a1a) is newer than this clone's origin/main (3c1d2e4f5a6b): git fetch origin.
zn upgraded: 5e8f5eaa4a1a -> 8a7b6c5d4e3f (/path/to/home/.local/bin/zn), engine 7c41d0e2a9f3.
zn: zn is already origin/main's (8a7b6c5d4e3f).
zn: ~/.local/bin is not on PATH, so the shells you open will not find zn: add it to PATH, or set ZN_BIN_DIR to a folder on PATH and run ./zn upgrade again.
zn is not installed: ./zn upgrade installs it (SETUP.md). Until then ./zn runs this checkout's engine.
zn: ZN_ENGINE=tree: running this tree's engine (/path/to/pickman/.worktree/R0070, 3c1d2e4f5a6b), not the installed one (8a7b6c5d4e3f).
```

## Touched modules
- `z-nile/go/cmd/zn/main.go`
- `z-nile/go/cmd/zn/front.go`
- `z-nile/go/cmd/zn/upgrade.go` (new)
- `z-nile/go/cmd/zn/version.go` (new)
- `z-nile/go/cmd/znpack/main.go`
- `z-nile/lib/znbuild.sh`
- `z-nile/lib/znupgrade.sh` (new)
- `zn`
- `z-nile/engine/payloadpath.luau` (new)
- `z-nile/engine/main.luau`
- `z-nile/engine/light.luau`
- `z-nile/engine/board.luau`
- `z-nile/engine/skills.luau`
- `z-nile/engine/dispatcher.luau`
- `z-nile/engine/costrow.luau`
- `z-nile/check.sh`
- `z-nile/tests/run.luau`
- `SETUP.md`
- `z-nile/skills/zz-rules/SKILL.md`
- `z-nile/skills/zz-arch/SKILL.md`
- `z-nile/skills/zz-test/SKILL.md`

## Affected specs
`main.go` 3 (`live-autostart`, `live-cli`, `livecall`) plus `go test ./...` in `z-nile/go`; `znbuild.sh` 0 (the watch
hole of E4: C1 adds its line to the watch map); `zn` 139, `main.luau` 305 (the affected gate); `SETUP.md` 1. The
executor reruns `lune run z-nile/affected` on the final list.

## Regression guard
- `z-nile/go/cmd/zn` and `internal/host` tests (the host front door's allowlist, lock and filters unchanged inside a
  host); `light-path` (its file list moves through `payloadpath`); the board specs; every spec that copies `zn` into a
  fixture (the shim runs the tree's engine under `PICKMAN_FENCE_SPECS=1`); `c0114/layout`, `c0120/finished` (they read
  `zn`).
- Overrides: none known; U5 of Draft B applies to the shim too.

## Unknowns & experiments
- E2, E3, E4, E6 above (run).
- U7 (does a sparse detached worktree of `z-nile/` at origin/main build zn?) Method: `git worktree add --no-checkout
  --detach`, `sparse-checkout set z-nile`, `znbuild.sh` there, under `.cache`. Fallback: a full detached worktree (7,777
  files).
- U8 (can the Go front door lower `RLIMIT_CPU` before `exec` as `cpu.sh` does?) Method: a Go test that execs `sh -c
  'ulimit -t'`. Fallback: exec through `bash -c 'source cpu.sh; zn_lower_cpu; exec "$@"'` from the payload.
- U9 (how many engine reads of `z-nile/...` are zn's own files, and how many the tree's?) Method: list every literal
  (`grep -c '"z-nile/'`: `light.luau` 40, `main.luau` 13, `skills.luau` 12, `watchcmd.luau` 5, `boundcmd.luau` 5,
  others 1 to 3) and classify each. Fallback: none; the list is the work of C3.
- U10 (does the jail let a spec start a fake `zn` from `.cache` on PATH?) Method: a probe spec. Fallback: the shim's
  installed-zn path is tested through `ZN_BIN=<fake>` honoured only under `PICKMAN_FENCE_SPECS=1`.

## Rules and mutants (the main rows; the executor completes them per slice)
| rule | spec :: case | mutant it kills | checked |
|---|---|---|---|
| upgrade builds only origin/main, atomically | upgrade :: AC1 | build the caller's tree; copy in place | reasoned |
| version names build and engine hash and the comparison | AC2 | hash the commit instead of the trees | reasoned |
| behind: state-changing refused, read-only warned | AC3 | warn only; refuse reads | reasoned |
| the installed engine runs in an old worktree | AC4 | run the tree's engine when present | reasoned |
| the launcher's guards are carried (each row of C-D7) | AC5 | drop the stdin test; no `ZN_CWD` | reasoned |
| the engine reads its own files from the payload | AC6 | a relative `z-nile/templates` read left | reasoned |
| the shim hands over except under tree/spec runs, falls back without install | AC7 | hand over inside a spec run | reasoned |
| a relative `--out` builds a real binary | AC8 | keep the `cd` before `go build -o` | reasoned |

## Acceptance criteria
### Checked
- AC1: `./zn upgrade` and `zn upgrade` build from origin/main in `.worktree/.zn-build`, replace `$ZN_BIN_DIR/zn` in one
  rename, print old and new, and refuse an older build without `--older`.
- AC2: `zn version` prints the build commit and the engine hash, and inside a repository whether origin/main's engine
  is the same, older, newer or not comparable.
- AC3: With an engine behind origin/main a state-changing command refuses with the upgrade message and a read-only
  command prints one line and runs.
- AC4: The installed zn run in a worktree whose branch is far behind main runs its embedded engine (its restack keeps a
  hand-rebased tip that the old engine would reset).
- AC5: Each row of C-D7 holds through the installed zn (a subfolder gives its project; approve's recording forms are
  refused without a terminal on stdin; the CPU limit is lowered; `work` reads the caller's worktree).
- AC6: With `ZN_PAYLOAD` set, the engine reads its templates, board page, vendor files, fence and measure scripts from
  the payload, and a tree whose copies differ is not read.
- AC7: The shim execs the installed zn for every engine command, runs the tree's engine under `ZN_ENGINE=tree` (one
  line) and in spec runs, and without an installed zn behaves as Draft B.
- AC8: `znbuild.sh --out <relative path>` writes a working binary at that path.
`check.sh` lines (added with the spec; the Go cases run by `go test` through one line):
```
SPEC="$A/installed-zn.spec.luau"
check "AC1: upgrade builds from origin/main and replaces zn in one rename" case_ok "AC1:"
check "AC2: zn version names its build, its engine and origin/main's" case_ok "AC2:"
check "AC3: an older zn refuses state-changing commands and warns on reads" case_ok "AC3:"
check "AC4: the installed zn runs its own engine in an old worktree" case_ok "AC4:"
check "AC5: the installed zn carries every guard and setting of the launcher" case_ok "AC5:"
check "AC6: the engine reads its own files from the payload" case_ok "AC6:"
check "AC7: ./zn hands over to the installed zn except for the tree's own tests and ZN_ENGINE=tree" case_ok "AC7:"
check "AC8: a relative --out builds a real binary" case_ok "AC8:"
```
### Observed
- OC1: the owner runs `./zn upgrade` once, opens a new terminal, and `zn version` says current; after the next engine
  merge a worker's `zn restack` refuses with `zn upgrade`, runs it, and goes on.

## Implementation steps (slices, each mergeable alone)
- **C1** (the first useful slice): `znbuild.sh`'s `--out` fix and engine hash; `znupgrade.sh`; `zn upgrade`, `zn
  version`; the front-door parity rows of C-D7; staleness (C-D3); the shim hands the raft-managing commands (restack
  first, Draft B's list) to the installed zn when it is installed and current; every other command stays on the shell
  launcher. SETUP.md's install step.
- **C2**: `payloadpath.luau` and every engine read of its own files (C-D6, f0428 step 8b for this repository).
- **C3**: the shim hands every engine command to the installed zn (C-D5); the gate and runner export `ZN_ENGINE=tree`.
- **C4**: zz-rules, zz-arch and zz-test say which zn runs what (C-D9), and the read-only warning line.

---

## How far the repository is from "zn is a Go executable with its own lifecycle" (plain answer)
Four steps, about one ticket of four slices (Draft C), roughly 1,450 lines:
1. Built already: the Go program carries Lune and the engine, extracts them once and checks them (f0427, f0428 steps
   1 to 4). Built from this repository it runs today's engine in an old worktree (E2).
2. Missing, C1: it cannot stand in for `./zn` yet (no top folder, no `ZN_TOP`/`ZN_CWD`, no stdin test for approvals,
   no CPU limit), nothing installs or upgrades it, and nothing compares its version with main.
3. Missing, C2: its engine still reads its helper files from the folder it runs in (f0428 step 8b).
4. Missing, C3 and C4: `./zn` does not hand over to it, and the skills and SETUP.md do not mention it.

## Guesses (each a product choice, with its alternative)
- G1: the act is `./zn restack <R-id> --origin-is-mine`. Alternative: `--ours` (reads like git's conflict side), or a
  separate `./zn vouch`.
- G2: "same patch" is the patch-id of the layer's whole change from its base on each side. Alternative: per-commit
  patch ids, or tree equality.
- G3: a different change is confirmed only by typing the layer's name. Alternative: the same `y/N` with a warning, or
  refuse different changes.
- G4: `a` covers only same-patch layers. Alternative: every listed layer.
- G5: it runs anywhere in the repository, the main checkout included. Alternative: only in the raft's worktree.
- G6: only the layers restack would refuse are asked. Alternative: every layer without a ref.
- G7: the record's audit trail is the ref's reflog. Alternative: a log file under `.cache`.
- G8: the printed form stays `./zn`, rewritten to the main checkout's zn only for a stale worktree. Alternative: `zn`
  everywhere.
- G9: a worktree hands over when its engine is behind origin/main by at least one engine commit. Alternative: always,
  or never.
- G10: a main checkout behind origin/main in its engine refuses the hand-over and names `zn sync` there. Alternative:
  hand over anyway (still newer than the worktree), or sync by itself.
- G11: `ZN_ENGINE=tree` may run a state-changing command only when the tree contains origin/main's engine. Alternative:
  never, or always.
- G12: zn installs to `~/.local/bin` (`ZN_BIN_DIR` overrides). Alternative: `/usr/local/bin`, or `GOBIN`.
- G13: zn is built only from origin/main, in a sparse build worktree. Alternative: from the main checkout's files.
- G14: an older zn refuses state-changing commands and warns on reads. Alternative: upgrade by itself, or warn only.
- G15: any session, an agent's included, may run `zn upgrade`. Alternative: the person only (O2).
- G16: the version is the build commit plus a hash of the engine's git trees. Alternative: the commit alone.
- G17: `./zn` becomes a shim to the installed zn; the gate and the runner keep the tree's engine through
  `ZN_ENGINE=tree`, silently. Alternative: remove `./zn`, or keep it as the tree's engine.
- G18: the marker's `writer` line is informational and the detection is the branch check. Alternative: a version that
  old engines refuse (impossible for engines that exist).
- G19: restack refuses in the main checkout. Alternative: leave it allowed.
- G20: C's tributary is delivery-and-landing. Alternative: omarchy, beside f0427 and f0428.

## Open to the human
- O1: Two optional changes to what the PreToolUse hook refuses (they change the hook's rules in
  `z-nile/engine/boundcmd.luau`, so they are shown to you before they land): refusing `restack ... --origin-is-mine`
  when wrapped in `script`, `expect` or the other forms it already refuses for approve (A1 step 7); and refusing
  `./zn restack`, `finish`, `start`, `commit` or `done` inside a worktree whose `./zn` is old and behind main (B-D7).
  Decision: add both, one, or neither.
- O2: May an agent session run `zn upgrade` by itself? It builds only origin/main's merged code, which is what an
  agent's `./zn` in the main checkout runs today, so it gives an agent nothing new; the alternative is that only you
  upgrade, and every session stops at the refusal (about ten times a day) until you do.
- O3: f0428's step 8b (the engine reads its own files from the payload) is done by C2 for this repository. Decision:
  move that step into C (f0428 then references C), or keep it in f0428 and make C depend on it.
- O4: d0434 is not finished in the tracker: its folder is in the backlog with `status: new-...` and `design: draft`, and
  its acceptance spec is not promoted, although PR #756 merged its code. Decision: who finishes it, and whether A and B
  wait for that.

## Could not determine
- How the worker ran main's engine in the R0070 worktree on 2026-11-24: by the launcher's code, `<main>/zn restack R0070
  --continue` from that worktree would have run in the main checkout (E1), yet the reflog shows the continuing rebase in
  the R0070 worktree. Ask the worker for the exact command.
- Whether agy sets an agent marker or runs its tools with a controlling terminal (U6).
- Whether an old engine's approval hash equals a new one's (U4).

## Commands for the lead (they publish; this task ran none of them)
In a capture worktree (z-idea), from the main checkout:
```
cd "$(./zn worktree capture-restack-follow-ups)" && ./zn sync
./zn new issue d restack-origin-is-mine --project z-nile --desc "Restack cannot be told an old branch is ours: layers pushed before d0434 have no refs/zn/pushed and stop every restack (R0070, R0100); the owner types git update-ref by hand."
./zn new issue d worktree-runs-old-zn --project z-nile --desc "A worktree's ./zn runs its own old engine: on 2026-11-24 ./zn restack R0070 in a worktree 150 commits behind main reset layer 1 off the resolved commit."
./zn new issue f zn-installed-lifecycle --project z-nile --desc "zn is one installed program with its own lifecycle (owner, 2026-11-24): the engine that runs never depends on the folder or branch."
```
For each new id: set `risk: risky` and `tributary:` in its frontmatter, `./zn guess <id> --step design --open "risk of
<id>" --chose "risky" --why "<the draft's one-line reason>"`, then `./zn idea <id> --text "<the draft's Problem and
Solution bullets>"`, `git add -A && git commit -m "tracker: new <ids> ..."`, `./zn land`, and `./zn spend <id> --phase
capture`. Then z-design for each (`./zn status <id> preparing` in `prep-<slug>`), taking its Design, messages, specs,
check lines and guesses from this file; the acceptance specs are written there, red, and the check.sh lines above
become each ticket's `check.sh` once its spec file exists.
