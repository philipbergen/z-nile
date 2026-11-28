# Idea review 002

## Findings

- F1: "If one of those mistakes happens again, it gets a new lesson under the `cause:` rule" contradicts the `repeats` rule. The earlier harvest entry for a pruned lesson cites the pruned id, not `one-off:`, so `--check` fails a `repeats` that names it. Unless a defect shipped, the recurrence cannot get a lesson. The idea also does not say whether that new lesson may reuse the pruned id, which the ledger rule fails from every unlisted item.
- F2: The Solution covers review findings only and is silent on `- note` sources (a user correction, a failed step, a subagent's candidate). A note must name lesson ids and cannot be `one-off:` (`z-nile/engine/lessons.luau:421`), and it has no `<stem> F<n>` for `repeats` to name. For 54 of the 231 pruned lessons the only citation is a note. As written, a lesson from a note fails `--check` unless a defect shipped, while the same correction recorded with `from:` is exempt.
- F3: `cause: repeats` does not require the named `one-off:` entry to be in a different item from the one that cites the lesson. The issue's Decided line says a lesson is for a mistake recurring across 2+ items, so two rounds of one item's review would satisfy the rule. "Earlier" also has no test a reader or `--check` can apply.
- F4: `cause: defect <f-id>` names the wrong kind of id. Defect issues carry `d` ids (`d0149` and `d0331` are `type: defect`), and `f` ids are features (`f0461` is `type: feature`).
- F5: "the 124 pruned lessons whose only citation is in a backlog or active item" is 126 on origin/main (`c530e048b`), counted with the engine's own `lessons.load` and `lessons.sources`. The split is 80 in backlog issues, 38 in active issues, 3 in backlog rafts and 5 in an active raft; the other 105 are in done items.
- F6: `./zn lessons --graduate` is not the smallest solution: no Problem sentence needs it, because the ledger is what unblocks graduation. `./zn lessons` already prints every lesson with its source count, most-cited first. At 3 or more citations the new flag lists 240 of the 415 lessons left after the prune, which does not single out candidates.
- F7: "the count of single-citation lessons grows with every review" is false as a universal. zz-rules (`SKILL.md:221`) says to write a new file only when no lesson fits, and z-design (`SKILL.md:72`) prefers a new source for an existing lesson. Today's harvests hold 3,938 entries that name lessons and 476 `one-off:` entries against 646 lesson files, so most findings add no file. The sentence gives no measured rate.

## Verdict

revise
