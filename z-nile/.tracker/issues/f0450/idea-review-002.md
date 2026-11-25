# Idea review 002

## Findings

- F1: Solution bullet 5 cannot hold for the case Problem bullet 14 names. A half-built sentence (f0423 S1 and S2, f0437 S2 at audit-B.md line 10; f0420's Scope decision and Decided lines at audit-A.md line 78) needs a line on both tickets saying which half each carries. "Appears on exactly one of the two" fails that split, or passes only by putting a half-built sentence whole on one ticket.
- F2: "Closing raft" has no test, so Solution bullets 1 to 4, 6 and 9 cannot be found true or false. The engine knows only "the stack changed no source file" (trace.luau lines 1148-1150), and the Problem says no rule names the route. The Solution also does not say what a code cell holds once a closing review's fix changes a source file: line 1166 then demands the stack's own files, while bullet 1 says every cell cites origin/main.
- F3: Solution bullet 9 is already true for every raft, so it is not part of the smallest solution. `cmd.done` fails with "waits for approval: <id> (no approval)" (z-nile/engine/main.luau lines 5477-5490) for any raft readied with `Lands: approved`, which every `ready` outside dispatch writes (lines 7086-7088). Under dispatch, `ready` asks for approval itself (zz-rules SKILL.md line 84). No Problem bullet says an unapproved ticket can land.
- F4: Solution bullet 7's second half cannot be checked. The Problem says the review files were never committed (audit-B.md line 86: `git log --all` holds none), so a `review-NNN.md` written now from a refute file or a pull request body is not the reviewer's text. No reader can compare it with the review it stands for, yet `./zn rounds` would count it as a round. The audits plan fresh rounds instead (audit-A.md line 88).
- F5: Non-goal 1 is not a fence. It leaves open whether Solution bullets 1 to 4 are built, while Solution bullet 1 says the idea is option (b). audit-C.md line 17 says the owner picks (a) or (b), and the owner's words quoted in Problem bullet 1 pick neither, so the idea's scope cannot be read from it.
- F6: Solution bullets 7 (guesses) and 8 are not this engine change. Recording inline guesses with `./zn guess` and writing check lines is each ticket's own prep under existing rules (audit-A.md lines 85-86; `ready` already needs a `check.sh` with a check, zz-rules SKILL.md line 84). As outcomes of f0450 they make its layer edit fifteen other tickets' files. Bullet 8 is also met by one check line per ticket, whatever the ticket's criteria.
- F7: The cited lines do not hold what Problem bullets 3 and 4 say about c0178 and d0434. d0434 is in none of the three audits, and c0178 appears only as c0179's dependency (audit-C.md lines 292, 298, 317). Bullet 4's citations (audit-A.md line 7, audit-B.md line 7) cover eight of the fourteen tickets. The tree does bear both out (d0434 built by #756, c0178 by #795), but the evidence named does not.
- F8: Problem bullet 12 contradicts bullet 11. Bullet 11 says f0427's 12 and f0428's 9 named specs "were never written" (audit-C.md lines 79 and 197; also f0423's AC8-AC16, audit-B.md line 85). Bullet 12 says the specs "are missing only from those tickets' check lines".

## Verdict

revise
