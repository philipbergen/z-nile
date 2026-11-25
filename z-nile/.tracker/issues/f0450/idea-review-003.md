# Idea review 003

## Findings

- F1: Solution bullet 2 does not tie a code cell to the merged change. Every file in the repository exists at any commit, so `path:lines@<commit>` passes for a file that commit never touched, whereas trace.luau line 1166 today demands a file the stack changed. f0420's code came in four pull requests (#703, #710, #748, #758): a `Closes:` line naming only 9e0b75761 (#758) lets every cell cite the other three's code, while the review briefs hold only #758's diff.
- F2: The solution is not the smallest. Adding the files the `Closes:` commits changed to the changed-source set (built at main.luau line 5342) lets trace.luau lines 1148-1168 run unchanged, with cells citing the code at the stack's head. That needs no `@<commit>` form, no Solution bullet 4 and no second half of bullet 3. The `@<commit>` check also still accepts lines that a later commit on main changed or removed.
- F3: Solution bullet 8 assumes a split makes exactly two tickets. audit-C.md lines 121-123 plan f0427 as the original plus two new tickets, and audit-A.md line 76 says f0420's outcome 11 can be its own ticket. A sentence moved to the second new ticket appears on neither ticket of the first pair, so `./zn audit` reports an error for a correct three-way split.
- F4: No Solution sentence changes the Problem's guesses bullet. After this is built, the approval of a closing ticket still covers the unbuilt part's guesses, and the fifth Non-goal leaves the one named remedy (the reverse split) to the owner.
- F5: The exception in Solution bullet 8 cannot be found true or false. `./zn audit` can check that a `Scope decision` line quotes a sentence, but not that it says "the half it carries".
- F6: Solution bullet 6 passes when each `Closes:` commit is on any one review's `Read:` line. A closing raft whose code review lists every commit passes with a final review that lists none, though audit-B.md line 12 says the final review carries the weight.
- F7: "So no code cell can ever cite the merged code" is false as written. trace.luau line 1166 checks only the path, so once a review fix changes a file, a cell can cite any merged lines in that file. What holds is that a cell cannot cite merged code in a file the stack did not change.
- F8: The second Non-goal cites audit-A.md line 88 for "review files that were never committed". Line 88 only lists the review rounds to run; the missing review files are in line 11.

## Verdict

revise
