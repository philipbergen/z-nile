# Idea review 001

## Findings

- F1: The Solution says the session "stops only once that raft has landed on main", but some of the raft's stops are ones the session cannot clear itself. The z-work skill (`z-nile/skills/z-work/SKILL.md:26`) says a raft with a member that is not approved ends at `wait` until the person runs `./zn approve`. Rule 5 of the same skill has a blocked raft write `questions.md` and run `./zn stop <R>`. In both cases the raft can't land without the person, and the third non-goal keeps that approval in place. So as written, the session would either loop forever or the Solution's sentence would be false. The idea needs to say what the session does when the next action is a `wait` that only a person can clear, or when the raft is blocked or stopped: does it hold and wait for the person, or does it stop and say why? Without that, nobody can check whether "stops only once landed" is true.

## Verdict

revise
