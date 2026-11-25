# Idea review 001

## Findings

- F1: Problem bullets 1 and 3 are false where they say there is "no way" and "no route" to close merged code. Bullets 4 and 5 describe that route (a closing raft whose trace passes with `none`), and audit-C.md lines 16-17 name it as option (a). `./zn done` taking only a raft id is not a barrier, because a ticket can be rafted (c0178 already is). The problem the evidence supports is that the route's code leg is checked by nothing.
- F2: Non-goal 1 is not a fence, because it leaves open the choice that decides whether Solution bullets 1-4 are needed at all. Audit-C.md line 19 calls it "the first thing to settle, because it decides the size of every item below". If the owner accepts option (a), the listed tickets close with no engine change, so the idea cannot claim to be the smallest solution while that is open.
- F3: Solution bullet 8 already holds, so a reader cannot find it false today. `isSpecForIssue` (`z-nile/engine/trace.luau` 883-907) accepts any `.spec.luau` under the home's `tests/` as the ticket's own, as audit-B.md line 8 says. Check lines already run tooling specs and `go test` in place (`z-nile/.tracker/issues/c0178/check.sh` AC2). What Problem bullet 8 shows missing is unwritten check lines on each ticket, not a capability.
- F4: Problem bullet 2 is false for "with no raft": c0178 has `raft: R0061` (`design: ready`, `status: prepared-…`, issues c0134, c0135, c0137, c0178). The same bullet counts "Rework counts shipped defects", which sits on the unmerged branch rework-shipped. Every Solution bullet covers only code "on main" and no non-goal fences it out, so it is in the problem and in neither the solution nor the fences.
- F5: Problem bullet 9's "a reverse split … is cleaner" is a preference, not a true-or-false statement, and Non-goal 3 then says the idea does not decide it. Solution bullet 5 ("one of the two tickets") cannot be checked without knowing which ticket closes. Solution bullet 6 restates a rule that exists (`z-nile/skills/z-design/SKILL.md` line 10; audit-B.md line 10) and "before it counts" names no command that refuses, so it too cannot be found true or false.
- F6: The evidence cannot be followed as cited. Problem bullet 1 places the audits in "the lead session's scratchpad folder closing/", which no reader can open. The files are at `z-nile/.tracker/issues/f0450/evidence/`, untracked.

## Verdict

revise
