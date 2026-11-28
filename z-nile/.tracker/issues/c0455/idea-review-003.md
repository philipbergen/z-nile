# Idea review 003

## Findings

- F1: Problem sentence 5 is false as written. c0455's Decided line sets graduation at "3-5+ citations"; "2+ items" there is the test for creating a lesson. `./zn lessons` already prints each lesson's citation count, most first (`lessons.luau:957`, `:993`). So "5 or more different items" (85 lessons) is the writer's own measure, not the Decided line's, which gives 240 at 3 citations and 142 at 5. It needs the human's answer or a recorded guess.
- F2: The new `--check` test only covers lessons with no `from:` key, and the Solution never stops a new lesson being written with one. The engine accepts any non-empty `from:` (`lessons.luau:145`), and zz-rules limits it in prose only (`SKILL.md:43`). A lead can therefore still write a lesson for a single finding by adding `from:`, so Problem sentence 2 stays open. The idea freezes the 78-line legacy list against additions but leaves this wider exemption unfenced.
- F3: The recurrence rule makes a lead edit another item's `harvest.md`, and the Solution does not say which earlier items may be edited. For a prepared member of a backlog raft, `harvest.md` is part of the hash on the raft's `grouped:` line (`raftplan.luau:469`), so the edit makes `ready` refuse that raft (`zz-rules/SKILL.md:207`). For an active item it is a file another worker's branch is writing. 126 of the pruned citations sit in exactly those items (83 backlog, 43 active). The idea does not show that a rule leaving the earlier item's file alone would fail, so this is not shown to be the smallest solution.

## Verdict

revise
