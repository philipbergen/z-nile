# Proposed lessons from c0161's design (for the lead to write; a prep subagent writes no lesson files)

## z-design/existence-checks-exclude-earlier-cycles
```
---
title: A check that a step happened ignores what an earlier cycle of the same item left
when: design
tags: [process, refusals, re-prep, records]
check: Can what an earlier cycle of this item left (an earlier prep that landed, an earlier scope's rounds still in this worktree, a round from before the design changed) satisfy this existence check, what in the artifact says which design it was made for, and who writes that record (is it someone other than the party whose change the check exists to catch)?
---
A check that asks only whether an artifact exists (a review round, an approval, a stamp) is satisfied by whatever an earlier cycle of the same item left behind. The proxy "not on origin/main" tells apart only the cycle that already landed; a scope reset in place keeps the earlier scope's rounds untracked in the same worktree, and a fix design that is approved and then rewritten into a closure leaves no boundary at all.

**Why:** c0161's design reviews 001 and 002 (F1 in each). The move to prepared accepted the newest design round in the folder, so a closure decided in a re-prep passed on the old approval (the captured Problem). Comparing with origin/main fixed the landed case and was wrong for c0181's scope reset in place. What held was a record of the design the round read, quoted in the round and compared with the design as it is.

**How to apply:** for each existence check, list the earlier cycles the skills describe (a reclaim, a scope reset, a fix turned into a closure) and ask what tells this cycle's artifact apart. Prefer an artifact that names what it was made for (a hash of the design it read) over a proxy for "new" (a number, a tracked state), have it written by someone other than the party whose change the check exists to catch (a record the author writes proves only what the author saw), and give every rewrite of ids (compact, remap, renumber) a re-record step.
```

## Note on z-design/reasoned-rows-claim-testable-reasons (c0161 design review 002 F2)
```
A reasoned row's stated reason is a claim about a fixture or a runner entry: check that the fixture puts the state the reason cites where the reason says (origin/main, or only the worktree), and that the runner's mutant edits the code the row names. c0161's row L3 said the case landed the raft's rounds on origin/main; the case wrote them in the worktree, and the runner's L3 mutated another argument, so it was equivalent and survived.
```

## Note on z-design/new-rules-migrate-existing-work (c0161 design review 001 F2)
```
A rule about where an artifact lives covers every era of the process that is still supported: the old prep's design reviews live in the raft's folder (R0044 has five rounds there and none in its member's), so a rule that looks only in the issue's folder refuses a reviewed design and demands a sixth review. Search the tree for the older shape before writing the rule, and name the items on it.
```

## Note on z-design/new-rules-migrate-existing-work (c0161 design review 003 F2)
```
"Existing work" means the normal flow's own artifacts as well as old items: measure how often the step the rule constrains happens today before calling the new step "one line". c0161's record made every edit after an approving round cost a new round; on origin/main 33 of the 44 newest approving rounds had been followed by `fixed` answers that edit the design, so most preps gain a round, a cost the user then had to decide with the number in front of them. Check: "On the last N real runs of this step, how many would the new rule refuse or make cost more, and is that number in the design and in the user's decision?"
```

## Note on z-design/fallbacks-name-the-modes-they-cover (c0161 design review 003 F3)
```
A fallback kept for one named item expires with it: c0161 kept a record-free path for the old prep so that R0044 would not need a sixth review; R0044 was released and readied the same day, and what remained was an exemption from the user's decided rule for every raft made the old way. Before keeping a fallback, search the tree for the items that need it today and name them; with none, remove it.
```

## Note on zz-test/no-vacuous-pass and zz-test/refusals-tested-on-both-sides (c0161 design review 006 F1; reviewers 005 F2 and 006 F1)
```
A "take" assertion on a command that prints both accepted and skipped items checks the line kind and the id together: `has(stdout, id)` also matches a `skip <id>:` or refusal line that names the id in its reason. Assert per id that a line of the accepted kind names it and no line of the refused kind does, and assert the accepted outcome (exit status and the item's new place), not only that the id appears. The mutants that find it are the ones that make the rule refuse everything (compare with another record), or read another source (the work tree) when the case's fixture makes both equal. Check: "Would this take assertion still pass if the command refused or skipped the item and printed its id in the reason?" c0161's review-read take side was unpinned in three rounds in a row (005 F1 `ready`/`recombine`, 005 F2 and 006 F1 `raft-plan`).
```

## Note on zz-arch/refusals-are-gate-checks (c0161 design review 006 F2)
```
A refusal that fires at a later read (rafting, readying) needs its recovery written on every documented path that produces the refused state, including the skills' own fix paths. c0161's check at next read refuses a prepared issue edited after its approving round; z-raft's documented way to change a rafted member (change it in the rafting branch, re-fold, land) lands exactly that state, and the refusal's recovery ("a new round, z-design 5.3") was a claim that a rafted issue cannot make (z-design's claim refuses an issue whose `raft:` names a raft). Check: "Which documented workflow can land the state this refusal refuses, and does that workflow say how to avoid or repair it, in the worktree where the person is?"
```

## Note on z-raft/rafted-member-changes-stay-in-the-raft (c0161 design review 006 F2 and 007 F1; for the lead to write, and its "fold it again at the end" advice is wrong as it stands)
```
How to apply, replaced: a change to a rafted member's design takes two landings, because `grouped:` is recorded from origin/main and `fold` refuses a member whose `raft:` on origin/main still names a raft. (1) In a rafting worktree `./zn unfold <R-id> <id>`, make the edit, add the member's approving design round (`./zn design-record <id>` quote, once c0161 lands), `./zn status <R-id> prepared`, and land. (2) In a second rafting worktree `./zn fold <R-id> <id>`, the coherence review if the raft has several members, `./zn status <R-id> prepared`, and land. The cost is one extra PR per in-raft member fix. A plain re-fold in the same PR is refused ("already belongs"), and a landed raft whose member was edited in it is refused by `./zn ready` ("changed on origin/main since … grouped it"). A chore that edits another prepared issue's design files runs the round for the edited issue in its own worktree.
```

## Note on zz-arch/refusals-are-gate-checks (c0161 design review 007 F1)
```
A recovery written for a refusal is run end to end, through the worktrees and commands the skill names, before it is written down. A recovery whose steps each pass alone can still be refused by an older check on the same path: c0161's first wording ("add the round in the rafting worktree, then re-fold") was refused by c0116's `grouped:` record, which reads origin/main, and a second try (unfold and fold in one PR) was refused by fold reading origin/main too. Check: "Has a case walked this recovery step by step as the skill words it, to the command that refused, and does that command now take it?"
```
